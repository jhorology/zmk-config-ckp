#!/bin/zsh -eu

PROJECT=$(realpath $0:h)

# configuration
# -----------------------------------
HOST_OS=$(uname)
[[ $HOST_OS = "Darwin" ]] && HOST_OS=macos
[[ $HOST_OS = "Linux" ]] && HOST_OS=linux
HOST_ARCHITECTURE=$(uname -m)
[[ $HOST_OS = "macos" ]] && [[ $HOST_ARCHITECTURE = "arm64" ]] && HOST_ARCHITECTURE=aarch64
ZEPHYR_VERSION=3.2.0
ZEPHYR_SDK_VERSION=0.15.2

# it is recommended to extract the Zephyr SDK bundle at one of the following default locations:
#
# $HOME
# $HOME/.local
# $HOME/.local/opt
# $HOME/bin
# /opt
# /usr/local
ZEPHYR_SDK_INSTALL_DIR=$HOME/.local

# Supported Toolchains:
#
# aarch64-zephyr-elf
# arc64-zephyr-elf
# arc-zephyr-elf
# arm-zephyr-eabi
# mips-zephyr-elf
# nios2-zephyr-elf
# riscv64-zephyr-elf
# sparc-zephyr-elf
# x86_64-zephyr-elf
# xtensa-espressif_esp32_zephyr-elf
# xtensa-espressif_esp32s2_zephyr-elf
# xtensa-intel_apl_adsp_zephyr-elf
# xtensa-intel_bdw_adsp_zephyr-elf
# xtensa-intel_byt_adsp_zephyr-elf
# xtensa-intel_s1000_zephyr-elf
# xtensa-nxp_imx_adsp_zephyr-elf
# xtensa-nxp_imx8m_adsp_zephyr-elf
# xtensa-sample_controller_zephyr-elf
TARGET_TOOLCHAINS=(arm-zephyr-eabi)

DOCKERFILE="Dockerfile.$(uname)"
DOCKER_IMAGE=my/zmk-dev-arm:stable
CONTAINER_NAME=zmk-build
UPDATE_BUILD=true
APPLY_PATCHES=true
CONTAINER_WORKSPACE_DIR=/workspace

# key: target name [1]=board:[2]=firmwre_name:[3]=DFU volume name
local -A KEYBOARDS=(
    bt60       bt60:bt60_hhkb_ec11:CKP
)
TARGETS=(bt60)


cd "$PROJECT"
#  override configuration
# -----------------------------------
[ -s .config ] &&  source .config


THIS_SCRIPT=$0

# options
# -----------------------------------
zparseopts -D -E -F -- \
           {h,-help}=help  \
           -clean=clean \
           -clean-modules=clean_modules \
           -clean-tools=clean_tools \
           -clean-all=clean_all \
           -setup=setup \
           -setup-docker=setup_docker \
           {s,-docker-shell}=docker_shell \
           {d,-with-docker}=with_docker \
           -with-setup=with_setup \
           {c,-with-clean}=with_clean \
           {w,-without-update}=without_update \
           {p,-without-patch}=without_patch \
           {f,-flash}=flash  \
    || return


# functions
# -----------------------------------
help_usage() {
    print -rC1 -- \
          "" \
          "Usage:" \
          "    $THIS_SCRIPT:t <-h|--help>                     help" \
          "    $THIS_SCRIPT:t --clean                         clean build folder" \
          "    $THIS_SCRIPT:t --clean-modules                 clean source moudules & build files" \
          "    $THIS_SCRIPT:t --clean-tools                   clean zephyr sdk & project build tools" \
          "    $THIS_SCRIPT:t --clean-all>                    clean build environment" \
          "    $THIS_SCRIPT:t --setup                         setup zephyr sdk & projtect build tools" \
          "    $THIS_SCRIPT:t --setup-docker                  create docker image" \
          "    $THIS_SCRIPT:t <-s|--docker-shell>             enter docker container shell" \
          "    $THIS_SCRIPT:t [build options...] [TARGETS..]  build firmwares" \
          "" \
          "build options:" \
          "    -c,--with-clean                  pre build clean up build & temporary files" \
          "    -d,--with-docker                 build with docker" \
          "    --with-setup                     pre build automatic setup" \
          "    -w,--without-update              don't sync remote repository" \
          "    -p,--without-patch               don't apply patches" \
          "    -f,--flash                       post build copy firmware to DFU drive" \
          "" \
          "available targets:"
    for target in ${(k)KEYBOARDS}; do
        print -rC2 -- "   ${target}:"  "${KEYBOARDS[$target]}"
    done
}

error_exit() {
    print -r "Error: $2" >&2
    exit $1
}


# prefix for platform spcific functions
case $HOST_OS in
    macos )
        os=macos
        ;;
    linux )
        if [[ -f /etc/fedora-release ]]; then
            os=fedora
        else
            # TODO
            error_exit 1 'unsupported platform.'
        fi
        ;;
    * )
        error_exit 1 'unsupported platform.'
        ;;
esac



clean() {
    cd "$PROJECT"
    rm -rf build
    find . -name "*~" -exec rm -f {} \;
    find . -name ".DS_Store" -exec rm -f {} \;
}

clean_modules() {
    cd "$PROJECT"
    clean()
    rm -rf dist
    rm -rf build
    rm -rf modules
    rm -rf zmk
    rm -rf zephyr
    rm -rf .west
}

clean_tools() {
    cd "$PROJECT"
    rm -rf .venv
    rm -rf "${ZEPHYR_SDK_VERSION}"
    rm -rf "${ZEPHYR_SDK_INSTALL_DIR}/${ZEPHYR_SDK_VERSION}"
    if [ ! -z "$(docker ps -q -a -f name=$CONTAINER_NAME)" ]; then
        docker rm -f  $CONTAINER_NAME $(docker ps -q -a -f name=$CONTAINER_NAME)
        sleep 5
    fi
    if [ ! -z "$(docker images -q $DOCKER_IMAGE)" ]; then
        docker rmi $DOCKER_IMAGE
    fi
}

clean_all() {
    cd "$PROJECT"
    clean_modules
    clean_tools
}

fedora_setup_docker() {
    # TODO
    echo "see https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-containers"
}

macos_setup_docker() {
    brew update
    brew install --cask docker
    brew cleanup
}

setup_docker() {
    if ! which docker &> /dev/null; then
        ${os}_setup_docker
        which docker &> /dev/null || \
            error_exit 1 "'docker' command not found. Check Docker.app cli setting."
    fi

    if [ -z "$(docker images -q $DOCKER_IMAGE)" ]; then
        docker build \
               --build-arg HOST_UID=$(id -u) \
               --build-arg HOST_GID=$(id -g) \
               --build-arg WORKSPACE_DIR=$CONTAINER_WORKSPACE_DIR \
               -t my/zmk-dev-arm:stable -f $DOCKERFILE .
    fi
}

docker_exec() {
    # create container
    if [ -z "$(docker ps -q -a -f name=$CONTAINER_NAME)" ]; then
        docker run -dit --init \
               -v $PROJECT:$CONTAINER_WORKSPACE_DIR \
               --name $CONTAINER_NAME \
               -w $CONTAINER_WORKSPACE_DIR \
               $DOCKER_IMAGE
    fi
    # exec
    docker exec $1 \
           -w $CONTAINER_WORKSPACE_DIR \
           $CONTAINER_NAME \
           bash
}

fedora_setup() {
    # https://docs.zephyrproject.org/3.2.0/develop/getting_started/index.html#select-and-update-os
    sudo dnf update
    sudo dnf install wget git cmake ninja-build gperf python3 ccache dtc wget xz file \
         make gcc SDL2-devel file-libs
    # gcc-multilib g++-multilib
    sudo dnf autoremove
    sudo dnf clean all
}

macos_setup() {
    # https://docs.zephyrproject.org/3.2.0/develop/getting_started/index.html#select-and-update-os
    brew update
    brew install wget git cmake ninja gperf python3 ccache qemu dtc libmagic ccls
    brew cleanup
}

setup() {
    cd "$PROJECT"
    ${os}_setup
    if [[ ! -d "${ZEPHYR_SDK_INSTALL_DIR}/zephyr-sdk-${ZEPHYR_SDK_VERSION}" ]]; then
        mkdir -p "$ZEPHYR_SDK_INSTALL_DIR"
        cd "$ZEPHYR_SDK_INSTALL_DIR"
        sdk_minimal_file_name="zephyr-sdk-${ZEPHYR_SDK_VERSION}_${HOST_OS}-${HOST_ARCHITECTURE}_minimal.tar.gz"
        wget "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}/${sdk_minimal_file_name}"
        tar xvf ${sdk_minimal_file_name}
        rm ${sdk_minimal_file_name}
    fi
    cd "${ZEPHYR_SDK_INSTALL_DIR}/zephyr-sdk-${ZEPHYR_SDK_VERSION}"
    if [[ ! -d "${TARGET_TOOLCHAIN}" ]]; then
        for toolchain in $TARGET_TOOLCHAINS; do
         ./setup.sh -h -c -t $toolchain
        done
    fi
    cd "$PROJECT"

    # zinit setting
    #
    # https://github.com/MichaelAquilina/zsh-autoswitch-virtualenv
    # export AUTOSWITCH_DEFAULT_PYTHON=python3
    # zinit load MichaelAquilina/zsh-autoswitch-virtualenv

    python3 -m venv .venv
    source .venv/bin/activate
    pip3 install west
    pip3 install -r https://raw.githubusercontent.com/zephyrproject-rtos/zephyr/v${ZEPHYR_VERSION}/scripts/requirements-base.txt
    pip3 install -r https://raw.githubusercontent.com/zephyrproject-rtos/zephyr/v${ZEPHYR_VERSION}/scripts/requirements-build-test.txt
    pip3 install -r https://raw.githubusercontent.com/zephyrproject-rtos/zephyr/v${ZEPHYR_VERSION}/scripts/requirements-run-test.txt
    pip3 cache purge
}

clangd_setting() {
}

ccls_setting() {
    cat <<EOS > "${PROJECT}/.ccls"
{
  "clang": {
     "resourceDir": "${ZEPHYR_SDK_INSTALL_DIR}/zephyr-sdk-${ZEPHYR_SDK_VERSION}/${TARGET_TOOLCHAIN}/${TARGET_TOOLCHAIN}",
     "clang.extraArgs": [
       "-gcc-toolchain=${ZEPHYR_SDK_INSTALL_DIR}/zephyr-sdk-${ZEPHYR_SDK_VERSION}/${TARGET_TOOLCHAIN}"
     ]
  },
  "compilationDatabaseDirectory": "${PROJECT}"
}
EOS
}


update() {
    cd "$PROJECT"
    if [ ! -d .west/ ]; then
        west init -l config
        west config build.cmake-args -- -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    fi

    if $UPDATE_BUILD; then
        rm -rf build
        if [ -d zmk ]; then
            # revert changes
            cd zmk
            git reset --hard HEAD
            git clean -dfx
            cd ..
        fi
        west update -n
        if $APPLY_PATCHES; then
            cd zmk
            git apply -3 --verbose ../patches/zmk_*.patch
            cd ..
        fi
        west zephyr-export
    fi
}

update_with_docker() {
    docker_exec -i <<-EOF
    if [ ! -d .west/ ]; then
        west init -l config
        west config build.cmake-args -- -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    fi
    if $UPDATE_BUILD; then
        rm -rf build
        if [ -d zmk ]; then
            # revert changes
            cd zmk
            git reset --hard HEAD
            git clean -dfx
            cd ..
        fi
        west update -n
        if $APPLY_PATCHES; then
            cd zmk
            git apply -3 --verbose ../patches/zmk_*.patch
            cd ..
        fi
        west zephyr-export
    fi
EOF
}

# $1 board
build() {
    board=$1
    west build -s zmk/app -b $board --build-dir build/$board -- -DZMK_CONFIG="${PROJECT}/config"
}

# $1 board
build_with_docker() {
    board=$1
    docker_exec -i <<-EOF
    west build -s zmk/app -b $1 --build-dir build/$board -- -DZMK_CONFIG="${CONTAINER_WORKSPACE_DIR}/config"
EOF
}


# copy & rename firmware
# $1 board
# $2 firmware name
# -----------------------------------
dist_firmware() {
    cd "$PROJECT"
    cd zmk
    version="$(date +"%Y%m%d")_zmk_$(git rev-parse --short HEAD)"
    cd ..
    mkdir -p dist
    src=build/${1}/zephyr/zmk.uf2
    dst=dist/bt60_hhkb_ec11_${version}.uf2
    cp $src $dst
    echo $dst
}


# $1 volume name
macos_dfu_volume() {
    echo /Volumes/$1
}

fedora_dfu_volume() {
    # TODO fedora on WSL2
    error_exit 1 "flashing firmware is not supported"
}

# $1 firmware file
# $2 volume name
flash_firmware() {
    src=$1
    dst_dir=$(${os}_dfu_volume $2)
    echo -n "Waiting for DFU volume:[$dst_dir] to be mounted"
    for ((i=0; i < 20; i+=1)); do
        echo -n "."
        if [[ -d "$dst_dir" ]]; then
            echo ""
            echo "copying file [$src] to ${dst_dir}..."
            sleep 1
            cp $src "$dst_dir"
            echo "flashing firmware finished successfully."
            break
        fi
        sleep 1
    done
}

cd "$PROJECT"


#  sub commands
# -----------------------------------
if (( $#help )); then
    help_usage
    return
elif (( $#clean )); then
    clean
    return
elif (( $#clean_all )); then
    clean_all
    return
elif (( $#clean_tools )); then
    clean_tools
    return
elif (( $#clean_modules )); then
    clean_modules
    return
elif (( $#docker_shell )); then
    setup_docker
    docker_exec -it
    return
elif (( $#setup )); then
    setup
    return
elif (( $#setup_docker )); then
    setup_docker
    return
fi

# build option parameters
# -----------------------------------
(( $#without_update )) && UPDATE_BUILD=false
(( $#without_patch )) && APPLY_PATCHES=false
(( $#@ )) && TARGETS=("$@")

[[ -d modules ]] || UPDATE_BUILD=true
[[ -d zephyr ]] || UPDATE_BUILD=true
[[ -d zmk ]] || UPDATE_BUILD=true
[[ -d .west ]] || UPDATE_BUILD=true

#  clean build
# -----------------------------------
if $UPDATE_BUILD || (( $#with_clean )); then
    clean
fi

# pre build setup
# -----------------------------------
if (( $#with_setup )); then
    if (( $#with_docker )); then
        setup_docker
    else
        setup
    fi
fi

# build
# -----------------------------------
if (( $#with_docker )); then
    update_with_docker
else
    update
fi
for target in $TARGETS; do
    kbd=(${(@s/:/)KEYBOARDS[$target]})
    board=$kbd[1]
    firmware_name=$kbd[2]
    dfu_volume_name=$kbd[3]
    if (( $#with_docker )); then
        build_with_docker $board
    else
        build $board
    fi
    firmware_file=$(dist_firmware $board $firmware_name)
    if (( $#flash )); then
        flash_firmware $firmware_file $dfu_volume_name
    fi
done

