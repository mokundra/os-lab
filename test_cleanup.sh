#!/bin/bash
set -euo pipefail

color1='\033[0;31m'
color2='\033[0;35m'
color3='\033[0;32m'
color4='\033[0;33m'
resetcolor='\033[0m'

PATHTODIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUPDIR="$PATHTODIR/cleanup.sh"

TESTDIR="$PATHTODIR/test_env"
LOGDIR="$TESTDIR/LOGS"
BACKUPDIR="$TESTDIR/backup"

TOTALSIZE=102400
LIMIT=90

info() { echo -e "${color4}[INFO]${resetcolor} $1"; }

normal() { echo -e "${color3}[NORMAL]${resetcolor} $1"; }

error() {
    echo -e "${color1}[ERROR]${resetcolor} $1"
    exit 1
}
start() {
    echo ""
    echo -e "${color4}[START]${resetcolor} $1"
}

cleanup_all() { rm -rf "$TESTDIR"; }

createenv() {
    rm -rf "$TESTDIR"
    mkdir -p "$LOGDIR/auth_service"
    mkdir -p "$LOGDIR/data_process_service"
    mkdir -p "$LOGDIR/system_event_handler_service"
    mkdir -p "$BACKUPDIR"
}

createfile() {
    local service="$1"
    local filename="$2"
    local size="$3"

    dd if=/dev/zero of="$LOGDIR/$service/$filename" bs=1M count="$size" status=none
}

countfiles() {
    local service="$1"

    find "$LOGDIR/$service" -maxdepth 1 -type f -name "${service}_*.log" | wc -l
}

archivecount() {
    find "$BACKUPDIR" -maxdepth 1 -type f -name "*.tar.gz" | wc -l
}

servicearchivecount() {
    local service="$1"

    find "$BACKUPDIR" -maxdepth 1 -type f -name "*_${service}_*.tar.gz" | wc -l
}



run_cleanup() {
    local usedsize="$1"
    local limit="${2:-90}"
    local backup="${3:-$BACKUPDIR}"

    export LAB1_TEST_MODE=1
    export LAB1_TEST_TOTAL_SIZE_KB="$TOTALSIZE"
    export LAB1_TEST_USED_SIZE_KB="$usedsize"

    "$CLEANUPDIR" "$LOGDIR" "$limit" "$backup"
}


#TEST 1

test_no_cleanup() {
    start "TEST 1: No cleanup below partition limit"
    createenv

    createfile "auth_service" "auth_service_2026_01_02_1767225600.log" 14

    createfile "auth_service" "auth_service_2026_01_02_1767312000.log" 14

    createfile "auth_service" "auth_service_2026_01_03_1767398400.log" 14

    local before
    before=$(countfiles "auth_service")

    run_cleanup 80000 >/dev/null 2>&1

    local after
    after=$(countfiles "auth_service")

    local archives
    archives=$(archivecount)

    if [[ "$after" -ne "$before" ]]; then
        error "Files were deleted although partition usage is below limit"
    fi

    if [[ "$archives" -ne 0 ]]; then
        error "Archive was created although cleanup was not required"
    fi

    normal "TEST 1 passed"
}

#TEST 2

test_one_service() {
    start "TEST 2: Cleanup only overloaded service"

    createenv

    createfile "auth_service" "auth_service_2026_01_01_1767225600.log" 14
    createfile "auth_service" "auth_service_2026_01_02_1767312000.log" 14
    createfile "auth_service" "auth_service_2026_01_03_1767398400.log" 14

    createfile "data_process_service" "data_process_service_2026_01_01_1767225600.log" 10
    createfile "data_process_service" "data_process_service_2026_01_02_1767312000.log" 10

    createfile "system_event_handler_service" "system_event_handler_service_2026_01_01_1767225600.log" 10
    createfile "system_event_handler_service" "system_event_handler_service_2026_01_02_1767312000.log" 10

    run_cleanup 95000 >/dev/null 2>&1

    local autharchives
    autharchives=$(servicearchivecount "auth_service")

    local dataarchives
    dataarchives=$(servicearchivecount "data_process_service")

    local systemarchives
    systemarchives=$(servicearchivecount "system_event_handler_service")


    if [[ "$autharchives" -ne 1 ]]; then
        error "Archive for auth_service was not created"
    fi

    if [[ "$dataarchives" -ne 0 ]]; then
        error "data_process_service was archived although it did not exceed its limit"
    fi

    if [[ "$systemarchives" -ne 0 ]]; then
        error "system_event_handler_service was archived although it did not exceed its limit"
    fi

    normal "TEST 2 passed"
}


#TEST 3

test_oldest_file() {
    start "TEST 3: Oldest file is archived first"

    createenv

    local oldest
    oldest="$LOGDIR/auth_service/auth_service_2026_01_01_1767225600.log"

    local middle
    middle="$LOGDIR/auth_service/auth_service_2026_01_02_1767312000.log"

    local newest
    newest="$LOGDIR/auth_service/auth_service_2026_01_03_1767398400.log"

    createfile "auth_service" "auth_service_2026_01_01_1767225600.log" 14

    createfile "auth_service" "auth_service_2026_01_02_1767312000.log" 14

    createfile "auth_service" "auth_service_2026_01_03_1767398400.log" 14

    run_cleanup 95000 >/dev/null 2>&1


    if [[ -f "$oldest" ]]; then
        error "Oldest file was not archived"
    fi

    if [[ ! -f "$middle" ]]; then
        error "Second file was archived although it was not required"
    fi

    if [[ ! -f "$newest" ]]; then
        error "Newest file was archived although it was not required"
    fi

    local archive
    archive=$(find "$BACKUPDIR" -maxdepth 1 -type f -name "*_auth_service_*.tar.gz" | head -n 1)

    if [[ -z "$archive" ]]; then
        error "Archive was not created"
    fi

    if ! tar -tzf "$archive" | grep -q "auth_service_2026_01_01_1767225600.log"; then
        error "Oldest file was not found inside archive"
    fi

    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        error "Created archive is corrupted"
    fi

    normal "TEST 3 passed"
}


#TEST 4

test_two_services() {
    start "TEST 4: Two overloaded services"

    createenv

    createfile "auth_service" "auth_service_2026_01_01_1767225600.log" 12
    createfile "auth_service" "auth_service_2026_01_02_1767312000.log" 12
    createfile "auth_service" "auth_service_2026_01_03_1767398400.log" 12

    createfile "data_process_service" "data_process_service_2026_01_01_1767225600.log" 12
    createfile "data_process_service" "data_process_service_2026_01_02_1767312000.log" 12
    createfile "data_process_service" "data_process_service_2026_01_03_1767398400.log" 12

    createfile "system_event_handler_service" "system_event_handler_service_2026_01_01_1767225600.log" 10
    createfile "system_event_handler_service" "system_event_handler_service_2026_01_02_1767312000.log" 10

    run_cleanup 95000 >/dev/null 2>&1

    local autharchives
    autharchives=$(servicearchivecount "auth_service")

    local dataarchives
    dataarchives=$(servicearchivecount "data_process_service")

    local systemarchives
    systemarchives=$(servicearchivecount "system_event_handler_service")

        if [[ "$autharchives" -ne 1 ]]; then
        error "auth_service archive was not created"
    fi

    if [[ "$dataarchives" -ne 1 ]]; then
        error "data_process_service archive was not created"
    fi

    if [[ "$systemarchives" -ne 0 ]]; then
        error "system_event_handler_service should not be archived"
    fi

    normal "TEST 4 passed"
}


# TEST 5
test_exact_limit() {
    start "TEST 5: Partition usage is exactly 90 percent"

    createenv


    createfile "auth_service" "auth_service_2026_01_01_1767225600.log" 14

    createfile "auth_service" "auth_service_2026_01_02_1767312000.log" 14

    createfile "auth_service" "auth_service_2026_01_03_1767398400.log" 14


    local before
    before=$(countfiles "auth_service")

    run_cleanup 92160 >/dev/null 2>&1

    local after
    after=$(countfiles "auth_service")

    local archives
    archives=$(archivecount)


    if [[ "$after" -ne "$before" ]]; then
        error "Files were deleted at exactly 90 percent"
    fi

    if [[ "$archives" -ne 0 ]]; then
        error "Archive was created at exactly 90 percent"
    fi

    normal "TEST 5 passed"
}


#TEST 6

test_errors() {
    start "TEST 6: Invalid environment"

    #Missing service directory
    createenv
    
    rm -rf "$LOGDIR/system_event_handler_service"

    if run_cleanup 95000 >/dev/null 2>&1; then
        error "Missing service directory was accepted"
    fi

    normal "6a: Missing service directory"

    #Backup inside LOGS
    createenv

    if run_cleanup 95000 90 "$LOGDIR/backup" >/dev/null 2>&1; then
        error "Backup directory inside LOGS was accepted"
    fi

    normal "6b: Backup inside LOGS"

    #Invalid limit
    createenv

    if run_cleanup 95000 150 >/dev/null 2>&1; then
        error "Invalid limit was accepted"
    fi

    normal "6c: Invalid limit"

    normal "TEST 6 passed"
}

#ENV check

start "Checking environment"

if [[ ! -f "$CLEANUPDIR" ]]; then
    error "cleanup.sh was not found"
fi

if [[ ! -x "$CLEANUPDIR" ]]; then
    chmod +x "$CLEANUPDIR"
fi

for cmd in bash tar find sort head cut du dd realpath basename xargs grep mountpoint wc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Required command not found: $cmd"
    fi
done

normal "Environment is ready"


#START

export LAB1_TEST_MODE=1
export LAB1_TEST_TOTAL_SIZE_KB="$TOTALSIZE"


echo ""
echo "----------------------------------------------------"
echo "LAB WORK #1 TESTS"
echo "----------------------------------------------------"

test_no_cleanup
test_one_service
test_oldest_file
test_two_services
test_exact_limit
test_errors
cleanup_all

unset LAB1_TEST_MODE
unset LAB1_TEST_TOTAL_SIZE_KB
unset LAB1_TEST_USED_SIZE_KB

echo ""
echo "----------------------------------------------------"
echo -e "${color3}ALL TESTS PASSED${resetcolor}"
echo "----------------------------------------------------"

exit 0

















