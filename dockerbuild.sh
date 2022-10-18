#!/bin/bash

set -emuo pipefail

DOCKER=${DOCKER:-"docker"} # So that we can invoke with DOCKERCMD=podman.
export DOCKER # So that test/tester.sh will use it.
TMPDIR=${TMPDIR:-"/var/tmp"}
export TMP=${TMP:-$TMPDIR}

trap docker_cleanup EXIT TERM INT

function docker_cleanup() {
    echo "Trap handler invoked. Stoping containers, dumping logs.."
    docker ps
    test/tester.sh stop clean
    echo "---- CONTAINER OUTPUT BEGIN ----"
    if [ -f "${TMP}/cat.out" ]; then
        tail -100 ${TMP}/cat.out
    fi
    echo "---- CONTAINER OUTPUT END ----"
    echo "Cleanup complete!"
}

function test_image() {
    echo "Starting container for testing..."
    test/tester.sh stop clean test_build || return 1

    echo "Starting tests..."
    test/tester.sh start test

    if [ $? -eq 0 ]; then
        echo "Tests PASSED"
    else
        echo "Tests FAILED"
    fi
}

if [ "${BUILD_SKIP:-false}" == "true" ]; then
    echo "BUILD skipped!"
else
    # Intentionally not using --no-cache here. Maintain the Dockerfile such that
    # cache can be used.
    $DOCKER build -t cloud-apps-baser --build-arg buildTime=$(date +%s) $* .
fi

if [ "${TESTS_SKIP:-false}" == "true" ]; then
    echo "TESTS skipped!"
else
    test_image
fi
