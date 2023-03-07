#!/bin/zsh -eu

PROJECT=$(realpath $0:h)
cd "$PROJECT"

zparseopts -D -E -F -- \
           {h,-help}=help  \
           {c,-clean}=clean  \
           {d,-docker}=docker  \
           {f,-flash}=flash  \
           {w,-without-update}=without_update \
    || return

# help
# -----------------------------------
if (( $#help )); then
    print -rC1 --      \
          "" \
          "Usage:" \
          "    $0:t <-h|--help>                   help" \
          "    $0:t <-c|--clean>                  clean build environment" \
          "    $0:t <-d|--docker>                 enter docker container shell" \
          "    $0:t [options...]                  build firmware" \
          "" \
          "options:" \
          "    -f,--flash                       post build copy firmware to DFU drive" \
          "    -w,--without-update              don't sync remote repository"
    return
fi

# configuration
# -----------------------------------
DOCKER_IMAGE=my/zmk-dev-arm:stable
UPDATE_BUILD_ENV=true
CONTAINER_WORK_DIR=/workdir

#  override configuration
# -----------------------------------
[ -s .config ] &&  source .config

#  clean
# -----------------------------------
if (( $#clean )); then
    rm -rf dist
    rm -rf build
    rm -rf modules
    rm -rf zmk
    rm -rf zephyr
    rm -rf .west
    docker rmi $DOCKER_IMAGE
    docker rmi zmkfirmware/zmk-dev-arm:stable
    return
fi

# option parameters
# -----------------------------------
(( $#without_update )) && UPDATE_BUILD_ENV=false

# pull docker  image
# -----------------------------------
# prevent creating files as root under WSL
DOCKERFILE="Dockerfile.$(uname)"
if [ -z "$( docker images -q $DOCKER_IMAGE)" ]; then
    docker build \
           --build-arg HOST_UID=$(id -u) \
           --build-arg HOST_GID=$(id -g) \
           --build-arg WORK_DIR=$CONTAINER_WORK_DIR \
           -t my/zmk-dev-arm:stable -f $DOCKERFILE .
fi

# enter docker container shell
# -----------------------------------
if (( $#docker )); then
    docker run -it --rm -v $PROJECT:$CONTAINER_WORK_DIR \
           --name zmk-build $DOCKER_IMAGE \
           bash
    return
fi

# docker build task
# -----------------------------------
docker run -it --rm -v $PROJECT:$CONTAINER_WORK_DIR \
       --env UPDATE_BUILD_ENV=$UPDATE_BUILD_ENV \
       --name zmk-build $DOCKER_IMAGE \
       $CONTAINER_WORK_DIR/container_build_task.sh

# copy & rename firmware
# -----------------------------------
pushd zmk
VERSION="$(date +"%Y%m%d")_zmk_$(git rev-parse --short HEAD)"
popd
mkdir -p dist
cp build/bt60/zephyr/zmk.uf2 dist/bt60_hhkb_ec11_${VERSION}.uf2

# flashfirmware
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


# BT65 is finally broken.
# cp build/bt65/zephyr/zmk.uf2 dist/bt65_tsangan_ec11x3_${VERSION}.uf2
