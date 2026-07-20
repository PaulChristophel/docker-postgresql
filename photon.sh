#!/usr/bin/env bash

set -euo pipefail

pushd "$(cd "$(dirname "$0")" && pwd)"

BASE=docker.io/photon:5.0@sha256:6db86de5ffc11d5c55e59d23790ad526b68e5bca4f030cb6a94e6136280866dd
PG_MAJOR=18
PG_VERSION=18.4
PG_SHA256=81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094
PG_CRON_VERSION=1.6.7
PGVECTOR_VERSION=0.8.5
PGAUDIT_VERSION=18.0
TAG="${PG_MAJOR}-standard-photon"
IMAGE_TITLE="CloudNativePG PostgreSQL on Photon"
IMAGE_DESCRIPTION="PostgreSQL built from upstream source on Photon OS for CloudNativePG."
IMAGE_AUTHORS="Paul Christophel <pmartin@gatech.edu>"
IMAGE_VENDOR="OIT"
IMAGE_OWNER="Platform Engineering"
IMAGE_SOURCE="https://github.com/PaulChristophel/docker-postgresql"
IMAGE_REPOSITORY="docker.io/pcm0/postgres"
IMAGE_URL="https://hub.docker.com/r/pcm0/postgres"
IMAGE_DOCUMENTATION="https://github.com/PaulChristophel/docker-postgresql#readme"
IMAGE_REVISION="$(git rev-parse HEAD)"
IMAGE_CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
IMAGE_LICENSES="PostgreSQL"

podman build \
    --build-arg BASE="${BASE}" \
    --build-arg PG_MAJOR="${PG_MAJOR}" \
    --build-arg PG_VERSION="${PG_VERSION}" \
    --build-arg PG_SHA256="${PG_SHA256}" \
    --build-arg PG_CRON_VERSION="${PG_CRON_VERSION}" \
    --build-arg PGVECTOR_VERSION="${PGVECTOR_VERSION}" \
    --build-arg PGAUDIT_VERSION="${PGAUDIT_VERSION}" \
    --build-arg IMAGE_TITLE="${IMAGE_TITLE}" \
    --build-arg IMAGE_DESCRIPTION="${IMAGE_DESCRIPTION}" \
    --build-arg IMAGE_AUTHORS="${IMAGE_AUTHORS}" \
    --build-arg IMAGE_VENDOR="${IMAGE_VENDOR}" \
    --build-arg IMAGE_OWNER="${IMAGE_OWNER}" \
    --build-arg IMAGE_SOURCE="${IMAGE_SOURCE}" \
    --build-arg IMAGE_REPOSITORY="${IMAGE_REPOSITORY}:${TAG}" \
    --build-arg IMAGE_URL="${IMAGE_URL}" \
    --build-arg IMAGE_DOCUMENTATION="${IMAGE_DOCUMENTATION}" \
    --build-arg IMAGE_REVISION="${IMAGE_REVISION}" \
    --build-arg IMAGE_CREATED="${IMAGE_CREATED}" \
    --build-arg IMAGE_LICENSES="${IMAGE_LICENSES}" \
    --platform=linux/amd64 \
    -f photon.dockerfile \
    -t "${IMAGE_REPOSITORY}:${TAG}"

podman push "${IMAGE_REPOSITORY}:${TAG}"
popd
