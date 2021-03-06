#! /bin/bash

set -e

log() {
    (echo -e "\e[91m\e[1m$*\e[0m")
}

cleanup() {
    if [ "$containerid" == "" ]; then
        return 0
    fi

    if [ "$1" == "error" ]; then
        log "error occurred, cleaning up..."
    elif [ "$1" != "" ]; then
        log "$1 received, please wait a few seconds for cleaning up..."
    else
        log "cleaning up..."
    fi

    docker ps -a | grep -q $containerid && docker rm -f $containerid
}

trap "cleanup SIGINT" SIGINT
trap "cleanup SIGTERM" SIGTERM
trap "cleanup error" 0
trap "cleanup" EXIT

CACHE=0
RECIPE=""
ARGS=""

for var in $@; do
    case "$1" in
        -c|--cache)
            if [ $CACHE -ne 0 ]; then
                log "warning: caching already enabled"
            fi
            CACHE=1
            ;;
        *)
            if [ "$RECIPE" != "" ]; then
                log "warning: ignoring argument: $1"
            else
                RECIPE="$1"
            fi
            ;;
    esac
    shift
done

if [ "$RECIPE" == "" ]; then
    log "usage: $0 [-c] name.yml"
    log ""
    log "\t-c, --cache\tEnable Recipe's caching by mounting the build cache directory into the container"
    exit 1
fi

if [ $(basename $RECIPE .yml) == "$RECIPE" ]; then
    RECIPE="$RECIPE.yml"
fi

if [ ! -f $RECIPE ]; then
    log "error: no such file or directory: $RECIPE"
    exit 1
fi

if [ $CACHE -ne 0 ]; then
    recipe_name=$(basename "$RECIPE" .yml)
    mkdir -p "$recipe_name"
    ARGS="-v $(readlink -f $recipe_name):/workspace/$recipe_name"
fi

log  "Building $RECIPE in a container..."

randstr=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
containerid=appimage-build-$randstr
imageid=appimage-build-$(id -u)

log "Building Docker container"
(set -xe; docker build -t $imageid --build-arg UID=$(id -u) --build-arg GID=$(id -g) .)

log "Running container"
mkdir -p out
set -xe
docker run -it \
    --name $containerid \
    --cap-add SYS_ADMIN \
    --device /dev/fuse \
    --security-opt apparmor:unconfined \
    --user $(id -u):$(id -g) \
    -v "$(readlink -f out):/workspace/out" \
    -v "$(readlink -f Recipe):/workspace/Recipe:ro" \
    -v "$(readlink -f $RECIPE):/workspace/$RECIPE:ro" \
    $ARGS \
    $imageid \
    ./Recipe $RECIPE || cleanup error
