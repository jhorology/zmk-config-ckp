#!/bin/zsh -eu

PROJECT=$(realpath $0:h)

# configuration
# -----------------------------------
HOST_OS=macos
HOST_ARCHITECTURE=$(uname -m)
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
TARGET_TOOLCHAIN=arm-zephyr-eabi

DOCKERFILE="Dockerfile.$(uname)"
DOCKER_IMAGE=my/zmk-dev-arm:stable
CONTAINER_NAME=zmk-build
UPDATE_BUILD=true
APPLY_PATCHES=true
CONTAINER_WORKSPACE_DIR=/workspace

THIS_SCRIPT=$0

cd "$PROJECT"

# options
# -----------------------------------
zparseopts -D -E -F -- \
           {h,-help}=help  \
           -clean-modules=clean_modules \
           -clean-tools=clean_tools \
           -clean-all=clean_all \
           -setup=setup \
           -setup-docker=setup_docker \
           {s,-docker-shell}=docker_shell \
           {d,-with-docker}=with_docker \
           -with-setup=with_setup \
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
          "    $THIS_SCRIPT:t <-h|--help>              help" \
          "    $THIS_SCRIPT:t <--clean-modules>        clean source moudules & build files" \
          "    $THIS_SCRIPT:t <--clean-tools>          clean zephyr sdk & project build tools" \
          "    $THIS_SCRIPT:t <--clean-all>            clean build environment" \
          "    $THIS_SCRIPT:t <--setup>                setup zephyr sdk & projtect build tools" \
          "    $THIS_SCRIPT:t <--setup-docker>         create docker image" \
          "    $THIS_SCRIPT:t <-s|--docker-shell>      enter docker container shell" \
          "    $THIS_SCRIPT:t [build options...]       build firmware" \
          "" \
          "build options:" \
          "    -d,--with-docker                 build with docker" \
          "    --with-setup                     pre build automatic setup" \
          "    -w,--without-update              don't sync remote repository" \
          "    -p,--without-patch               don't apply patches" \
          "    -f,--flash                       post build copy firmware to DFU drive"
}

error_exit() {
    print -r "Error: $2" >&2
    exit $1
}


clean_modules() {
    cd "$PROJECT"
    rm -rf dist
    rm -rf build
    rm -rf modules
    rm -rf zmk
    rm -rf zephyr
}

clean_tools() {
    cd "$PROJECT"
    rm -rf .venv
    rm -rf "${ZEPHYR_SDK_VERSION}"
    rm -rf "${ZEPHYR_SDK_INSTALL_DIR}/${ZEPHYR_SDK_VERSION}"
    if [ ! -z "$(docker ps -q -a -f name=$CONTAINER_NAME)" ]; then
        docker rm -f  $CONTAINER_NAME $(docker ps -q -a -f name=$CONTAINER_NAME)
        sleep 1
    fi
    if [ ! -z "$(docker images -q $DOCKER_IMAGE)" ]; then
        docker rmi $DOCKER_IMAGE
    fi
}

clean_all() {
    cd "$PROJECT"
    find . -name "*~" -exec rm -f {} \;
    find . -name ".DS_Store" -exec rm -f {} \;
    clean_modules
    clean_tools
}

setup_docker_macos() {
    brew update
    brew install --cask docker
    brew cleanup
}

setup_docker() {
    # TODO fedora on WSL
    if [ $HOST_OS = "macos" ]; then
        setup_docker_macos
    else
        error_exit 1 "Unsupported host OS."
    fi
    which docker &> /dev/null || \
        error_exit 1 "'docker' command not found. Check Docker.app cli setting."
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

setup_macos() {
    brew update
    brew install wget git cmake ninja gperf python3 ccache qemu dtc wget libmagic ccls
    brew cleanup

    if [[ ! -d "${ZEPHYR_SDK_INSTALL_DIR}/zephyr-sdk-${ZEPHYR_SDK_VERSION}" ]]; then
        mkdir -p "$ZEPHYR_SDK_INSTALL_DIR"
        cd "$ZEPHYR_SDK_INSTALL_DIR"
        sdk_minimal_file_name="zephyr-sdk-${ZEPHYR_SDK_VERSION}_${HOST_OS}-${HOST_ARCHITECTURE}_minimal.tar.gz"
        wget -q "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}/${sdk_minimal_file_name}"
        tar xvf ${sdk_minimal_file_name}
        cd zephyr-sdk-${ZEPHYR_SDK_VERSION}
        if [[ ! -d "${TARGET_TOOLCHAIN}" ]]; then
            ./setup.sh -h -c -t $TARGET_TOOLCHAIN
        fi
        rm ${sdk_minimal_file_name}
    fi
}

setup() {
    # TODO fedora on WSL
    if [ $HOST_OS = "macos" ]; then
        setup_macos
    else
        error_exit 1 "Unsupported host OS."
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
  "compilationDatabaseDirectory": "${PROJECT}/build/"
}
EOS
}

build() {
    cd "$PROJECT"
    if [ ! -d .west/ ]; then
        west init -l config
        west config build.cmake-args -- -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    fi

    if $UPDATE_BUILD; then
        rm -rf build
        if [ -d zmk ]; then
            # revert changes
            cd "$PROJECT/zmk"
            git reset --hard HEAD
            git clean -dfx
        fi
        cd "$PROJECT"
        west update -n
        cd "${PROJECT}/zmk"
        if $APPLY_PATCHES; then
            git apply -3 --verbose ../patches/zmk_*.patch
        fi
        cd "$PROJECT"
        west zephyr-export
    fi
    cd "$PROJECT"
    west build -s zmk/app -b bt60 -- -DZMK_CONFIG="${PROJECT}/config"
    mv build/compile_commands.json .
}

build_with_docker() {
    cd "$PROJECT"
    if [ ! -d .west/ ]; then
        docker_exec -i <<-EOF
          west init -l config
          west config build.cmake-args -- -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
EOF
    fi

    if $UPDATE_BUILD; then
        rm -rf build
        if [ -d zmk ]; then
            # revert changes
            docker_exec -i <<-EOF
              cd zmk
              git reset --hard HEAD
              git clean -dfx
EOF
        fi
        docker_exec -i <<-EOF
          west update -n
EOF
        if $APPLY_PATCHES; then
            docker_exec -i <<-"EOF"
              cd zmk
              git apply -3 --verbose $(ls ../patches/zmk_*.patch)
EOF
        fi
        docker_exec -i <<-EOF
          west zephyr-export
EOF
    fi
    docker_exec -i <<-EOF
      west build -s zmk/app -b bt60 -- -DZMK_CONFIG=${CONTAINER_WORKSPACE_DIR}/config
EOF
    # TODO lang server inside docker
    #  - lsp-tramp-connection dosen't work with macos
    #  - ccls binary is not aveilable for linux/arm
    rm build/compile_commands.json
}

cd "$PROJECT"

#  override configuration
# -----------------------------------
[ -s .config ] &&  source .config

#  sub commands
# -----------------------------------
if (( $#help )); then
    help_usage
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
fi

# build option parameters
# -----------------------------------
(( $#without_update )) && UPDATE_BUILD=false
(( $#without_patch )) && APPLY_PATCHES=false

[[ -d modules ]] || UPDATE_BUILD=true
[[ -d zephyr ]] || UPDATE_BUILD=true
[[ -d zmk ]] || UPDATE_BUILD=true
[[ -d .west ]] || UPDATE_BUILD=true

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
    build_with_docker
else
    build
fi

# copy & rename firmware
# -----------------------------------
cd "$PROJECT/zmk"

VERSION="$(date +"%Y%m%d")_zmk_$(git rev-parse --short HEAD)"

cd "$PROJECT"

mkdir -p dist
cp build/zephyr/zmk.uf2 dist/bt60_hhkb_ec11_${VERSION}.uf2

# flash firmware
# -----------------------------------
UF2_FLASH_VOLUME=""
if (( $#flash )); then
    if [[ $(uname) == "Darwin" ]]; then
        UF2_FLASH_VOLUME="/Volumes/CKP"
    fi

    # TODO other platform

    if [[ ! -z "$UF2_FLASH_VOLUME" ]]; then
        echo -n "Waiting for DFU volume to be mounted"
        for ((i=0; i < 20; i+=1)); do
            echo -n "."
            if [[ -d "$UF2_FLASH_VOLUME" ]]; then
                echo ""
                echo "copying file [bt60_hhkb_ec11_${VERSION}.uf2] to ${UF2_FLASH_VOLUME}..."
                sleep 1
                cp dist/bt60_hhkb_ec11_${VERSION}.uf2 "$UF2_FLASH_VOLUME"
                echo "flashing firmware finished successfully."
                break
            fi
            sleep 1
        done
    fi
fi
