#!/bin/zsh -eu

PROJECT=$(realpath $0:h)
cd "$PROJECT"

zparseopts -D -E -F -- \
           {h,-help}=help  \
           {c,-clean}=clean  \
           {d,-docker}=docker  \
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

# cop & rename firmware
# -----------------------------------
pushd zmk
VERSION="$(date +"%Y%m%d")_zmk_$(git rev-parse --short HEAD)"
popd
mkdir -p dist
cp build/zephyr/zmk.uf2 dist/$(git branch --show-current)_${VERSION}.uf2
