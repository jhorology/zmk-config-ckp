#!/bin/bash

PROJECT=$(dirname $(realpath $0))
cd $PROJECT

if [ ! -d .west/ ]; then
    west init -l config
    UPDATE_BUILD_ENV=true
fi

if $UPDATE_BUILD_ENV; then
    west update
    west zephyr-export
fi
west build -s zmk/app -b bt60 -- -DZMK_CONFIG="${PROJECT}/config"

