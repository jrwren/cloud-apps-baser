#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

[[ -r /env.sh ]] && source /env.sh
MetricsHost=${MetricsHost:-lmarelay-lmabuf${NOMAD_META_consuldc}.wbx2.com}

UA="User-Agent: cce-health-checker"
ERROR_LOG_PATH="/alloc/logs/check-frontend.stderr.0"
HEALTH_CHECK_CURL_COMMAND=(curl -N -H "$UA" --connect-timeout 2 --max-time 6 -sik https://127.0.0.1:${NOMAD_PORT_https}/${1:-} --trace-ascii /tmp/check_trace)

if "${HEALTH_CHECK_CURL_COMMAND[@]}" | head -1 | grep -qs 200; then
    curl -si -XPOST "http://${MetricsHost}:8186/write?db=metrics" --connect-timeout 2 --max-time 3 --data-binary "health,environment=${environment},cluster=${NOMAD_DC},service=${APPLICATION_NAME},host=${HOSTNAME},instance_index=${NOMAD_ALLOC_INDEX},status=online value=1" 2>&1 >/dev/null || true
    echo "online"
    exit 0
else
    curl -si -XPOST "http://${MetricsHost}:8186/write?db=metrics" --connect-timeout 2 --max-time 3 --data-binary "health,environment=${environment},cluster=${NOMAD_DC},service=${APPLICATION_NAME},host=${HOSTNAME},instance_index=${NOMAD_ALLOC_INDEX},status=offline value=0" 2>&1 >/dev/null || true
    echo "offline"
    echo "*************************************DETAIL STATS************************************" >> $ERROR_LOG_PATH
    echo -e "Failed time: $(date)" >> $ERROR_LOG_PATH
    echo -e "Curl command: \n$(cat /tmp/check_trace)" >> $ERROR_LOG_PATH
    echo -e "Resource stats: \n$(top -bn1)" >> $ERROR_LOG_PATH
    echo -e "Running processes: \n$(ps -elf)" >> $ERROR_LOG_PATH
    echo -e "Number of established connections: $(pgrep -f haproxy | xargs -I {} -t -n 1 sh -c 'ls -l /proc/{}/fd | wc -l' 2>/dev/null)" >> $ERROR_LOG_PATH
    echo -e "Connections with Send-Q > 0: \n$(netstat -atn|awk '{if($3>0) print $0}'|sort -k3nr|head -n 5)" >> $ERROR_LOG_PATH
    echo -e "Haproxy stats: \n$(echo 'show info;show stat;show table' | socat /var/run/haproxy.sock stdio)" >> $ERROR_LOG_PATH
    echo -e "Disk stats: \n$(df)" >> $ERROR_LOG_PATH
    echo "************************************************************************************" >> $ERROR_LOG_PATH
    exit 2
fi
