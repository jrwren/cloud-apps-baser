#!/bin/bash -e

TMP=${WORKSPACE:-/tmp}/cat
LOCAL_HOST="${LOCAL_HOST:-localhost}"
RED='\033[0;31m'
GRE='\033[0;32m'
YEL='\033[0;33m'
NC='\033[0m' # No Color

mkdir -p ${TMP}

function log() {
    printf "${YEL}$(date): $*${NC}\n"
}

function log_pass() {
    printf "${GRE}$(date): $*${NC}\n"
}

function log_fail() {
    printf "${RED}$(date): $*${NC}\n"
    return 1
}