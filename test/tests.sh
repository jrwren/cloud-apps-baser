#!/bin/bash

# This script defines a simple test harness to do basic testing on
# the image. The script needs to run inside the container.
#

function run_tests() {
  log "Running tests ..."
  total_tests=0
  passed_tests=0
  failed_tests=0
  all_tests=$(typeset -F | sed "s/declare -f //g" | grep '^__assert_')
  if [ ! -z "${TESTS_TO_RUN}" ]; then
      all_tests="${TESTS_TO_RUN}"
  else
      __test_setup
  fi
  for test in ${all_tests}
  do
      total_tests=$((total_tests + 1))
      log "TEST ${test} >>>>> started"
      if ${test}; then
          passed_tests=$((passed_tests + 1))
          log "TEST ${test} <<<<< PASS"
      else
          failed_tests=$((failed_tests + 1))
          log "TEST ${test} <<<<< FAIL"
      fi
  done
  log "Test run complete. Results: total/pass/fail: ${total_tests}/${passed_tests}/${failed_tests}"
  return ${failed_tests}
}

function run_in_container() {
  echo "Running command in container[$*]"
  bash -c "$@"
  status=$?
  echo "Command exited with status: [${status}]"
  return ${status}
}

function __test_setup() {
    log "Test SETUP running..."
}

function __assert_nothing() {
    echo "OK"
}

function __assert_https_port_is_open() {
    curl --output /dev/null --silent --head --insecure https://localhost:8881 || return 1
}

function __assert_can_read_ping_service_name() {
    [[ test -eq \
        "$(curl -s --insecure https://localhost:8881/api/v1/ping | jq -r .serviceName)" ]] || return 1
}

function skip__assert_stress_1m() {
    log "Running 10s warmup..."
    /hey -c 50 -z 10s -m GET https://localhost:8881/test/api/v1/ping > /dev/null 2>&1
    log "Running 15s stress test..."
    /hey -c 50 -z 15s -m GET https://localhost:8881/test/api/v1/ping
}

function check_url_ok() {
    echo "Checking url - $1"
    status=$(curl --output /dev/null \
        --write-out "%{http_code}" \
        --connect-timeout 10 \
        --max-time 10 \
        --silent \
        --insecure $1)
    [ "${status}" == "200" ] || return 1
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/common.sh
cd ${DIR}
run_tests
