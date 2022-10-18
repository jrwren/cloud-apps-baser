#!/bin/bash -e

# This script defines a simple test harness to do basic testing on
# the image.
#
DOCKER=${DOCKER:-"docker"}
export DOCKER_API_VERSION='1.38'

CERT_NAME="test"

IMAGENAME=cloud-apps-baser

function usage() {
    cat << END_HELP
Run as
  ./tester.sh [all] [build] [run] [test] [clean]

  all     - run all phases
  build   - build $IMAGENAME & $IMAGENAME-test images.
  start   - starts a container using $IMAGENAME-test image.
  test    - run tests defined in this script (functions prefixed __assert_)
  stop    - stop container
  clean   - cleanup containers and images

Examples:
  # Run selective tests
  $ TESTS_TO_RUN="__assert_app_start __assert_app_response" && ./tester.sh test

  # Run selective phases
  $ ./tester.sh clean start test stop

  # Run all phases
  $ ./tester.sh all
END_HELP
  exit 1
}

function cleanup() {
    $DOCKER kill $($DOCKER ps -qf "name=$IMAGENAME-test") > /dev/null 2>&1 || log "Container doesn't exist. Already stopped?"
    $DOCKER rm -f $IMAGENAME-test > /dev/null 2>&1 || log "Container doesn't exist. Already removed?"
    $DOCKER rmi $IMAGENAME-test > /dev/null 2>&1 || log  "Image doesn't exist. Already removed?"
    #$DOCKER rmi -f $IMAGENAME
    log "Cleanup complete!"
}

function create_certs() {
  log "Generating certs..."
  rm -rf ${TMP}/${CERT_NAME}.*
  openssl req \
    -nodes -newkey rsa:2048 \
    -keyout ${TMP}/${CERT_NAME}.key \
    -out ${TMP}/${CERT_NAME}.csr \
    -subj "/C=US/ST=CA/L=SJ/O=jrwren/OU=xmtp/CN=example.com"

  openssl x509 -req -days 365 \
    -in ${TMP}/${CERT_NAME}.csr \
    -signkey ${TMP}/${CERT_NAME}.key \
    -out ${TMP}/${CERT_NAME}.crt

  cat ${TMP}/${CERT_NAME}.crt ${TMP}/${CERT_NAME}.key > ${TMP}/${CERT_NAME}.pem
  cp ${TMP}/${CERT_NAME}.pem ${DIR}/certificates
}

function build_test_container() {
  log "Building $IMAGENAME-test TEST image..."
  [ ! -f "/${TMP}/${CERT_NAME}.pem" ] && create_certs
  $DOCKER build --no-cache \
    -t $IMAGENAME-test \
    ${DIR}
}

function start_container() {
  if [ -f "/.dockerenv" ]; then
      log "docker-inside-docker detected"
      #export DOCKER_OPTS="--net spark-build"
      log "Docker networks:"
      $DOCKER network ls
      for n in $($DOCKER network ls -q)
      do
          log "Network $n"
          $DOCKER network inspect $n
      done
  fi
  log "Starting $IMAGENAME-test container ..."
  $DOCKER run -d --rm $* ${DOCKER_OPTS} \
    -e buildTime=$(date +%s) \
    -p 8881:8881 \
    --name $IMAGENAME-test \
    $IMAGENAME-test

  mkdir -p ${TMP}
  $DOCKER inspect $IMAGENAME-test > ${TMP}/cat.out 2>&1
  $DOCKER logs -f $IMAGENAME-test >> ${TMP}/cat.out 2>&1 &
  wait_for_ports
}

function wait_for_ports() {
  timeout=300
  status_retries=5
  sleep 10

  run_in_container "cat /etc/hosts" || log "FAILED to fetch /etc/hosts"

  log "Waiting for ports...  ${LOCAL_HOST}"
  until run_in_container "curl --output /dev/null --silent --head --insecure https://${LOCAL_HOST}:8881" ; do
    printf '.'
    sleep 10
    # check for timeout
    timeout=$((timeout-10))
    if [ ${timeout} -le 0 ]; then
      log_fail "Timedout waiting for ports. Aborting..."
      return 1
    fi
    # check if container is still up
    status=$($DOCKER inspect -f {{.State.Running}} $IMAGENAME-test)
    if [ "${status}" != "true" ]; then
      status_retries=$((status_retries-1))
      if [ ${status_retries} -gt 0 ]; then
        log_fail "Container seems to have exited. running: [${status}]. Retrying..."
      fi
        log_fail "Container seems to have exited. running: [${status}]. Aborting..."
        return 1
    fi
  done
  echo "Connected!"
}

function stop_container() {
    log "Stopping & removing container..."
    $DOCKER kill $($DOCKER ps -qf "name=$IMAGENAME-test") > /dev/null 2>&1 || log "Error stopping container. Already stopped?"
    $DOCKER rm -f $IMAGENAME-test > /dev/null 2>&1 || log "Error removing container. Already removed?"
}

function run_in_container() {
  echo "Running command in container [$*]"
  $DOCKER exec \
      $IMAGENAME-test \
      bash -c "$@"
  status=$?
  echo "Command exited with status: [${status}]"
  return ${status}
}

function dump_stack() {
    # dump the call frames
    echo "======== stacktrace ========"
    local frame=0
    while caller $frame; do
        ((frame++));
    done
    echo "============================"
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/common.sh
cd ${DIR}
ARGS=$*
if [ $# -eq 0 ] || [ "${ARGS}" == "help" ]; then
    usage
elif [ "${ARGS}" == "all" ]; then
    ARGS="build start test stop clean"
fi

log "Running build with args: ${ARGS}"

for cmd in ${ARGS}
do
  case ${cmd} in
    "build")
      build_test_container
      ;;
    "test_build")
      create_certs
      build_test_container
      ;;
    "start")
      start_container
      ;;
    "ports")
      wait_for_ports
      ;;
    "test")
      run_in_container /test/tests.sh
      ;;
    "stop")
      stop_container
      ;;
    "clean")
      cleanup
      ;;
    *)
      log "Unrecognized command - ${cmd}"
      break;
  esac
done


