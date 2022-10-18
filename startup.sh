#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

trap drainhandler TERM INT

log() {
    echo "$(date): $*"
}

BASEIMGNAME="cloud-apps-baser"

drainhandler() {
  set +e
  log "$BASEIMGNAME: SHUTDOWN: received SIGINT or SIGTERM, breaking consul state and notifying service"
  if [ -d "/etc/filebeat/conf.d" ]; then
    rm -f /etc/filebeat/conf.d/stdlogs-${NOMAD_ALLOC_ID}.yml || true
  fi
  # emit a shutdown metric, tag deployment/non-deployment based on deploy time
  graceTime=3600
  nowTime=$(date +%s)
  if [[ ! -v buildTime ]];then buildTime=$nowTime ; fi
  buildTimeValue=${buildTime%.*}
  runTime=$(($nowTime-$buildTimeValue))

  if [ "$runTime" -gt "$graceTime" ]
  then
    echo "non-deployment shut down"
    curl -si -XPOST "http://${MetricsHost}:8186/write?db=metrics" --connect-timeout 2 --max-time 3 --data-binary "health,deployment=false,environment=${environment:-dev},service=${APPLICATION_NAME},host=${HOSTNAME},instance_index=${NOMAD_ALLOC_INDEX} shutdown=1,shutdown_seconds=${runTime},buildTime=${buildTimeValue},shutdownTime=${nowTime}" 2>&1 >/dev/null || true
  else
    echo "deployment shut down"
    curl -si -XPOST "http://${MetricsHost}:8186/write?db=metrics" --connect-timeout 2 --max-time 3 --data-binary "health,deployment=true,environment=${environment:-dev},service=${APPLICATION_NAME},host=${HOSTNAME},instance_index=${NOMAD_ALLOC_INDEX} shutdown=1,shutdown_seconds=${runTime},buildTime=${buildTimeValue},shutdownTime=${nowTime}" 2>&1 >/dev/null || true
  fi

  log "BASEIMGNAME: SHUTDOWN: service in maintenance mode, forcing front-end check failure"
  cp -rf /check-frontend-quiesce.sh /check-frontend.sh
  chmod a+x /check-frontend.sh
  log "$BASEIMGNAME: SHUTDOWN: front-end check set to fail, sleeping for ${postDrainPreShutdownPause:-15} seconds . . ."
  sleep ${postDrainPreShutdownPause:-15}
  log "$BASEIMGNAME: SHUTDOWN: sleep complete, passing SIGINT to application process"
  trap - CHLD
  kill -SIGINT $APPPID
  log "$BASEIMGNAME: SHUTDOWN: SIGINT passed to application, soft shutdown complete, waiting for hard kill for ${preShutdownPause:-30} seconds. . ."
  sleep ${preShutdownPause:-30}
  set -e
}

exithandler() {
  pgrep -x haproxy > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    sleep 3
    pgrep -x haproxy > /dev/null 2>&1
    if [ $? -ne 0 ]; then
      haproxy -D -m ${proxyMemory:-240} -f /etc/haproxy/haproxy.cfg -q &
    fi
  fi
  if kill -0 $APPPID; then
    : # SIGCHLD received, but all child processes alive, doing nothing"
  else
    log "SIGCHLD received, killing child processes"
    rm -f /etc/filebeat/conf.d/stdlogs-${NOMAD_ALLOC_ID}.yml || true
    kill ${HAPROXYPID} || true
    kill ${APPPID} || true
    sleep 3
    kill -9 $HAPROXYPID || true
    kill -9 $APPPID || true
    if [ -x /drain-addon.sh ]; then
      log "Executing drain-addon script"
      /drain-addon.sh
    fi
    exit 1
  fi
}

log "Container startup begin"
[[ -r /env.sh ]] && source /env.sh
now=$(date +%s)
buildTime=${buildTime:-$now}
NOMAD_META_consuldc=${NOMAD_META_consuldc:-dc1}
MetricsHost=${MetricsHost:-lmarelay-lmabuf${NOMAD_META_consuldc}.wbx2.com}

export IMAGE_SETTINGS+="|IMAGE_TAG=${IMAGE_TAG:-unset}|PARENT_IMAGE=${PARENT_IMAGE:-unset}"

if [ -d "/etc/filebeat/conf.d" ]; then
  cp /stdlogs.yml /etc/filebeat/conf.d/stdlogs-${NOMAD_ALLOC_ID}.yml
  sed -i -e "s/NOMAD_ALLOC_ID/${NOMAD_ALLOC_ID}/g" /etc/filebeat/conf.d/stdlogs-${NOMAD_ALLOC_ID}.yml
  sed -i -e "s/NOMAD_META_CONSULDC/${NOMAD_META_CONSULDC}/g" /etc/filebeat/conf.d/stdlogs-${NOMAD_ALLOC_ID}.yml
  sed -i -e "s/logstash_tags/${logstash_tags:-${NOMAD_TASK_NAME}}/g" /etc/filebeat/conf.d/stdlogs-${NOMAD_ALLOC_ID}.yml
fi

if [ -x /pre-launch.sh ]; then
  log "Executing pre-launch script"
  /pre-launch.sh
elif [ -f /pre-launch.sh ]; then
  echo "Pre-launch exists, but not executable: $(ls -la /pre-launch.sh)"
else
  echo "There is no pre-launch.sh on this container"
fi

# run.sh must write /run/app.pid
/run.sh &
i=0
while [[ ! -e /run/app.pid && $i -lt 60 ]]; do
  i=$((i+1)) ; sleep 1
done
APPPID=$(cat /run/app.pid)
# TODO: poll for app to be ready before starting haproxy to reduce 503 errors on startup.
# Allow apps to do their own TLS termination by setting NOHAPROXY.
log "Rendering haproxy config"
MAXSSLRATE=${MAXSSLRATE:-1000} /usr/bin/gucci -o missingkey=default /etc/haproxy/haproxy.cfg.tpl > /etc/haproxy/haproxy.cfg
if [[ ! -v NOHAPROXY ]]; then
  log "Starting haproxy"
  haproxy -D -m ${proxyMemory:-240} -f /etc/haproxy/haproxy.cfg -q &
  ps auxww
fi

READY=true

# emit a startup metric, tag deployment/non-deployment based on deploy time
graceTime=600
nowTime=$(date +%s)
if [[ ! -v buildTime ]];then buildTime=$nowTime ; fi
buildTimeValue=${buildTime%.*}
runTime=$(($nowTime-$buildTimeValue))

if [ "$runTime" -gt "$graceTime" ]
then
  echo "non-deployment start up"
  [[ -v MetricsHost ]] && curl -si -XPOST "http://${MetricsHost}:8186/write?db=metrics" --connect-timeout 2 --max-time 3 --data-binary "health,deployment=false,environment=${environment},service=${APPLICATION_NAME},host=${HOSTNAME},instance_index=${NOMAD_ALLOC_INDEX} startup=1,startup_seconds=${runTime},buildTime=${buildTimeValue},startTime=${nowTime}" 2>&1 >/dev/null || true
else
  echo "deployment start up"
  [[ -v MetricsHost ]] && curl -si -XPOST "http://${MetricsHost}:8186/write?db=metrics" --connect-timeout 2 --max-time 3 --data-binary "health,deployment=true,environment=${environment},service=${APPLICATION_NAME},host=${HOSTNAME},instance_index=${NOMAD_ALLOC_INDEX} startup=1,startup_seconds=${runTime},buildTime=${buildTimeValue},startTime=${nowTime}" 2>&1 >/dev/null || true
fi

log "Container startup end"
set -x
trap exithandler CHLD

wait
