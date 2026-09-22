#!/bin/bash
set -euo pipefail

DEVICE="${1:-}"
MOUNTDIR="${2:-/LOGS}"

color1='\033[0;31m'
color2='\033[0;35m'
color3='\033[0;32m'
color4='\033[0;33m'
resetcolor='\033[0m'

error() { echo -e "${color1}[ERROR]${resetcolor} $1" >&2; }
info() { echo -e "${color2}[INFO]${resetcolor} $1"; }
warn() { echo -e "${color3}[WARN]${resetcolor} $1"; }
normal() { echo -e "${color4}[NORMAL]${resetcolor} $1"; }


if [ -z "$DEVICE" ]; then
    error "Disk partition is not specified"
    echo "Using: $0 <device> [mount_directory]"
    exit 1
fi

if ! command -v mount >/dev/null 2>&1; then
    error "mount command was not found"
    exit 1
fi

if ! command -v mountpoint >/dev/null 2>&1; then
    error "mountpoint command was not found"
    exit 1
fi

mkdir -p "$MOUNTDIR"

if mountpoint -q "$MOUNTDIR"; then
    normal "$MOUNTDIR is already mounted"
    exit 0
fi

info "Device: $DEVICE"
info "Mount directory: $MOUNTDIR"

if [[ "$DEVICE" =~ ^[A-Za-z]:$ ]]; then
    info "Windows drive detected: $DEVICE"

    if ! mount -t drvfs "$DEVICE" "$MOUNTDIR"; then
        error "Failed to mount Windows drive"
        exit 1
    fi
else
    if [ ! -b "$DEVICE" ]; then
        error "Device does not exist or is not a block device: $DEVICE"
        exit 1
    fi

    info "Linux block device detected: $DEVICE"

    if ! mount "$DEVICE" "$MOUNTDIR"; then
        error "Failed to mount Linux partition"
        exit 1
    fi
fi

normal "Partition was mounted successfully"

if ! mountpoint -q "$MOUNTDIR"; then
    error "$MOUNTDIR is not a mount point after mount command"
    exit 1
fi

mkdir -p "$MOUNTDIR/auth_service"
mkdir -p "$MOUNTDIR/data_process_service"
mkdir -p "$MOUNTDIR/system_event_handler_service"

normal "LOGS partition is ready"

exit 0

