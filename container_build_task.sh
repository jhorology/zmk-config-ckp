#!/bin/bash -e

PROJECT=$(dirname $(realpath $0))
cd $PROJECT

[ ! -d modules ] && UPDATE_BUILD_ENV=true
[ ! -d zephyr ] && UPDATE_BUILD_ENV=true
[ ! -d zmk ] && UPDATE_BUILD_ENV=true

if [ ! -d .west/ ]; then
    west init -l config
    UPDATE_BUILD_ENV=true
fi

if $UPDATE_BUILD_ENV; then
    if [ -d zmk ]; then
        # revert changes
        cd zmk
        git reset --hard HEAD
        git clean -dfx
        cd $PROJECT
    fi
    west update -n
    west zephyr-export
    cd zmk
    for patch in ../patches/zmk_*.patch; do
        patch --verbose -p1 < $patch
    done
    cd $PROJECT
fi
west build -s zmk/app -b bt60 --build-dir build/bt60 -- -DZMK_CONFIG="${PROJECT}/config"
west build -s zmk/app -b bt65 --build-dir build/bt65 -- -DZMK_CONFIG="${PROJECT}/config"
