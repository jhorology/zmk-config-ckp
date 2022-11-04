#!/bin/zsh -eu

PROJECT=$(realpath $0:h)
cd "$PROJECT"

zparseopts -D -E -F -- \
           {h,-help}=help  \
           -without-update=without_update \
    || return


if (( $#help )); then
    print -rC1 --      \
          "Usage:" \
          "$0:t <-h|--help>                                            help" \
          "$0:t [options...]                                           build firmware" \
          "" \
          "options:" \
          "  -w,--without-update              don't sync remote repository"
    return
fi

# configuration
# -----------------------------------
DOCKER_IMAGE=my/zmk-dev-arm:stable
UPDATE_BUILD_ENV=true

#  override configuration
# -----------------------------------
[ -s .config ] &&  source .config

# option parameters
# -----------------------------------
(( $#without_update )) && UPDATE_BUILD_ENV=false

# pull docker  image
# -----------------------------------
[ -z "$(docker image ls | grep $DOCKER_IMAGE)" ] && \
    docker build -t my/zmk-dev-arm:stable .

# setup build env
# -----------------------------------
if $UPDATE_BUILD_ENV; then
    # revert changes
    pushd zmk
    git reset --hard HEAD
    git clean -dfx
    popd
fi

docker run -it --rm -v $PROJECT:/workdir --env UPDATE_BUILD_ENV=$UPDATE_BUILD_ENV --name zmk-build $DOCKER_IMAGE /workdir/container_build_task.sh

pushd zmk
VERSION="$(date +"%Y%m%d")_zmk_$(git rev-parse --short HEAD)"
popd

mkdir -p dist
cp build/zephyr/zmk.uf2 dist/$(git branch --show-current)_${VERSION}.uf2
