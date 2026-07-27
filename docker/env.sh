#!/usr/bin/env bash

DOCKER_UID=$(id -u)
DOCKER_GID=$(id -g)

echo "DOCKER_UID=$DOCKER_UID" > .env
echo "DOCKER_GID=$DOCKER_GID" >> .env
