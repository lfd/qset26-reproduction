#!/usr/bin/env bash

DC="docker compose -f docker/docker-compose.yml"
TARGET="dev"

case "$1" in
  build)
    $DC build ${TARGET}
    ;;
  up)
    $DC up -d ${TARGET}
    ;;
  down)
    $DC down ${TARGET}
    ;;
  shell)
    $DC exec ${TARGET} bash
    ;;
  *)
    echo "Usage: $0 {build|up|down|shell}"
    exit 1
esac
