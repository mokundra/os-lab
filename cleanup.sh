#!/bin/bash
set -euo pipefail

PATHTODIR="${1:-/LOGS}"
LIMIT="${2:-90}"
BACKUPDIR="${3:-./backup}"
ARCHIVESTART="logs_backup"

color1='\033[0;31m'
color2='\033[0;35m'
color3='\033[0;32m'
color4='\033[0;33m'
resetcolor='\033[0m'

error() { echo -e "${color1}[ERROR]${resetcolor} $1" >&2; }
info() { echo -e "${color2}[INFO]${resetcolor} $1"; }
warn() { echo -e "${color3}[WARN]${resetcolor} $1"; }
normal() { echo -e "${color4}[NORMAL]${resetcolor} $1"; }

if [ ! -d "$PATHTODIR" ]; then
    error "The LOGS folder does not exist: $PATHTODIR"
    exit 1
fi

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [[ "$LIMIT" -lt 0 ]] || [[ "$LIMIT" -gt 99 ]]; then
    error "The limit must be a number from 0 to 99"
    exit 1
fi

PATHTODIR="$(realpath "$PATHTODIR")"

if [ "${LAB1_TEST_MODE:-0}" != "1" ]; then
    if ! mountpoint -q "$PATHTODIR"; then
        error "The LOGS folder is not mounted as a separate partition: $PATHTODIR"
        exit 1
    fi

    info "The LOGS folder is mounted as a separate partition"
fi

AUTHDIR="$PATHTODIR/auth_service"
DATADIR="$PATHTODIR/data_process_service"
SYSTEMDIR="$PATHTODIR/system_event_handler_service"

for DIR in "$AUTHDIR" "$DATADIR" "$SYSTEMDIR";do
    if [ ! -d "$DIR" ]; then
        error "Required service folder does not exist: $DIR"
        exit 1
    fi
    
    if [ ! -r "$DIR" ]; then
        error "No rights to read the folder: $DIR"
        exit 1
    fi

    if [ ! -w "$DIR" ]; then
        error "No rights to modify the folder: $DIR"
        exit 1
    fi
done

mkdir -p "$BACKUPDIR"

BACKUPDIR="$(realpath "$BACKUPDIR")"

if [[ "$BACKUPDIR/" == "$PATHTODIR/"* ]]; then
    error "Backup folder must not be inside the LOGS partition"
    exit 1
fi

if [ ! -w "$BACKUPDIR" ]; then
    error "No rights to write to the backup folder: $BACKUPDIR"
    exit 1
fi

info "Folder with logs: $PATHTODIR"
info "Occupancy limit: $LIMIT%"
info "Backup folder: $BACKUPDIR"

if [[ "${LAB1_TEST_MODE:-0}" = "1" ]]; then
    TOTALSIZE="${LAB1_TEST_TOTAL_SIZE_KB:-0}"
    USEDSIZE="${LAB1_TEST_USED_SIZE_KB:-0}"

    if [[ "$TOTALSIZE" -le 0 ]] || [[ "$USEDSIZE" -lt 0 ]]; then
        error "Incorrect test filesystem size"
        exit 1
    fi
else
    TOTALSIZE=$(df --output=size -k "$PATHTODIR" 2>/dev/null | tail -1) || true
    USEDSIZE=$(df --output=used -k "$PATHTODIR" 2>/dev/null | tail -1) || true
fi

if [[ -z "$TOTALSIZE" ]] || [[ "$TOTALSIZE" -eq 0 ]]; then
    error "Couldn't get the partition size"
    exit 1
fi
 
if [[ -z "$USEDSIZE" ]]; then
    error "Couldn't get the used space of the partition"
    exit 1
fi

USAGE=$((USEDSIZE * 100 / TOTALSIZE))
info "Current partition fullness: ${USAGE}%"
    
if [[ $((USEDSIZE * 100)) -le $((TOTALSIZE * LIMIT)) ]]; then
    normal "Fullness is ok. No cleaning required"
    exit 0
fi
    
MAXLOGSIZE=$((TOTALSIZE * LIMIT / 100))
SERVICELIMIT=$((MAXLOGSIZE / 3))

warn "Partition fullness ${USAGE}% exceeds the limit ${LIMIT}%"
info "Maximum allowed size for all logs: ${MAXLOGSIZE} KB"
info "Limit for one service folder: ${SERVICELIMIT} KB"

TOTALARCHIVED=0

for SERVICEDIR in "$AUTHDIR" "$DATADIR" "$SYSTEMDIR"; do
    SERVICENAME=$(basename "$SERVICEDIR")
    SERVICESIZE=$(du -sk "$SERVICEDIR" 2>/dev/null | cut -f1) || true

    if [[ -z "$SERVICESIZE" ]]; then
        warn "Couldn't get size of $SERVICENAME"
        continue
    fi

    if [[ "$SERVICESIZE" -le "$SERVICELIMIT" ]]; then
        normal "$SERVICENAME does not exceed its 1/3 limit"
        continue
    fi

    NEEDTOFREE=$((SERVICESIZE - SERVICELIMIT))
    warn "$SERVICENAME exceeds its limit. Need to free at least ${NEEDTOFREE} KB"

    FILES=$(find "$SERVICEDIR" -maxdepth 1 -type f -name "${SERVICENAME}_*.log" 2>/dev/null | sort)

    if [ -z "$FILES" ]; then
        warn "There are no .log files to archive in $SERVICENAME"
        continue
    fi

    TMP="/tmp/files_to_archive_$$.txt"
    rm -f "$TMP"
    touch "$TMP"

    FREESIZE=0
    COUNTFILES=0

    for FILE in $FILES; do
        FILESIZE=$(du -k "$FILE" 2>/dev/null | cut -f1) || FILESIZE=0
        echo "$FILE" >> "$TMP"
        FREESIZE=$((FREESIZE + FILESIZE))
        COUNTFILES=$((COUNTFILES + 1))
        if [[ "$FREESIZE" -ge "$NEEDTOFREE" ]]; then 
            break
        fi
    done

    if [[ "$COUNTFILES" -eq 0 ]]; then
        rm -f "$TMP"
        warn "No files were selected for archiving"
        continue
    fi

    info "Selected ${COUNTFILES} oldest files"

    TIME=$(date +%Y%m%d_%H%M%S)
    ARCHIVEPATH="$BACKUPDIR/${ARCHIVESTART}_${SERVICENAME}_${TIME}_$$.tar.gz"

    if tar -czf "$ARCHIVEPATH" -T "$TMP" 2>/dev/null; then 
        normal "Archive was created: $ARCHIVEPATH"
    else
        error "Archive creation error for $SERVICENAME"
        rm -f "$TMP"
        exit 1
    fi

    if ! tar -tzf "$ARCHIVEPATH" >/dev/null 2>&1; then
        error "Archive verification failed: $ARCHIVEPATH"
        rm -f "$TMP"
        exit 1
    fi
    
    cat "$TMP" | xargs rm -f
    rm -f "$TMP"

    TOTALARCHIVED=$((TOTALARCHIVED + COUNTFILES))
    normal "Archived and deleted files from $SERVICENAME: $COUNTFILES"

    NEWSIZE=$(du -sk "$SERVICEDIR" 2>/dev/null | cut -f1) || true
    info "$SERVICENAME size after cleanup: ${NEWSIZE} KB"

    if [[ "$NEWSIZE" -gt "$SERVICELIMIT" ]]; then
        warn "$SERVICENAME is still above its limit. There may be non-log files in the folder"
    fi
done

echo ""
normal "Cleaning is complete"
info "Total archived files: $TOTALARCHIVED"

if [ "${LAB1_TEST_MODE:-0}" != "1" ]; then
    FINALTOTAL=$(df --output=size -k "$PATHTODIR" 2>/dev/null | tail -1) || true
    FINALUSED=$(df --output=used -k "$PATHTODIR" 2>/dev/null | tail -1) || true

    if [[ -n "$FINALTOTAL" ]] && [[ -n "$FINALUSED" ]] && [[ "$FINALTOTAL" -gt 0 ]]; then
        FINALUSAGE=$((FINALUSED * 100 / FINALTOTAL))
        info "Final partition fullness: ${FINALUSAGE}%"
    fi
fi

BACKUPSIZE=$(du -sh "$BACKUPDIR" 2>/dev/null | cut -f1 || echo "0")
info "Size of the backup folder: $BACKUPSIZE"

exit 0











