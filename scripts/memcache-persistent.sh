#!/usr/bin/env bash

set -euo pipefail

bold=$(tput bold)
normal=$(tput sgr0)

# Defaults
MEMCACHE_BINARY_DEFAULT="$(which memcached)"
MEMCACHE_CACHE_SIZE_MB_DEFAULT="128"
MEMCACHE_ITEM_SIZE_DEFAULT="8m"
MEMCACHE_PERSISTENCE_FILE_NAME_DEFAULT="memory_file"
MEMCACHE_PERSISTENCE_STATE_DIR_DEFAULT="/cache/state"
MEMCACHE_PERSISTENCE_MEMFS_DIR_DEFAULT="/cache/memfs"

# Input envvars
MEMCACHE_BINARY="${MEMCACHE_BINARY:-"$MEMCACHE_BINARY_DEFAULT"}"
MEMCACHE_CACHE_SIZE_MB="${MEMCACHE_CACHE_SIZE_MB:-"$MEMCACHE_CACHE_SIZE_MB_DEFAULT"}"
MEMCACHE_ITEM_SIZE="${MEMCACHE_ITEM_SIZE:-"$MEMCACHE_ITEM_SIZE_DEFAULT"}"
MEMCACHE_PERSISTENCE_FILE_NAME="${MEMCACHE_PERSISTENCE_FILE_NAME:-"$MEMCACHE_PERSISTENCE_FILE_NAME_DEFAULT"}"
MEMCACHE_PERSISTENCE_STATE_DIR="${MEMCACHE_PERSISTENCE_STATE_DIR:-"$MEMCACHE_PERSISTENCE_STATE_DIR_DEFAULT"}"
MEMCACHE_PERSISTENCE_MEMFS_DIR="${MEMCACHE_PERSISTENCE_MEMFS_DIR:-"$MEMCACHE_PERSISTENCE_MEMFS_DIR_DEFAULT"}"

# Derived envvars
MEMCACHE_PERSISTENCE_STATE_FILE="$MEMCACHE_PERSISTENCE_STATE_DIR/$MEMCACHE_PERSISTENCE_FILE_NAME"
MEMCACHE_PERSISTENCE_MEMFS_FILE="$MEMCACHE_PERSISTENCE_MEMFS_DIR/$MEMCACHE_PERSISTENCE_FILE_NAME"

function help {
  echo "Usage: $0"
  echo ""
  echo "Traditional memcache-related environment variables"
  echo "  ${bold}MEMCACHE_BINARY${normal}"
  echo "    Path to the memcache binary to use instead of default one by PATH"
  echo "    Default: $MEMCACHE_BINARY_DEFAULT"
  echo "  ${bold}MEMCACHE_CACHE_SIZE_MB${normal}"
  echo "    memcache cache size as per memory-limit argument (megabytes)"
  echo "    Default: $MEMCACHE_CACHE_SIZE_MB_DEFAULT"
  echo "  ${bold}MEMCACHE_ITEM_SIZE${normal}"
  echo "    memcache maximum item size as per max-item-size argument (unit must be specified, e.g.: \"8m\")"
  echo "    Default: $MEMCACHE_ITEM_SIZE_DEFAULT"
  echo ""
  echo "Persistence related environment variables"
  echo "  ${bold}MEMCACHE_PERSISTENCE_STATE_DIR${normal}"
  echo "    Persistent storage directory for the cache file. No trailing slash."
  echo "    Default: $MEMCACHE_PERSISTENCE_STATE_DIR_DEFAULT"
  echo "  ${bold}MEMCACHE_PERSISTENCE_MEMFS_DIR${normal}"
  echo "    Runtime memory-backed directory containing the cache file. No trailing slash."
  echo "    Default: $MEMCACHE_PERSISTENCE_MEMFS_DIR_DEFAULT"
  echo "  ${bold}MEMCACHE_PERSISTENCE_FILE_NAME${normal}"
  echo "    Name to use for the cache file within the persistence directories"
  echo "    Default: $MEMCACHE_PERSISTENCE_FILE_NAME_DEFAULT"
}

if [ -n "$*" ]; then
  echo "Found script arguments \"$*\" but arguments are ignored!"
  echo ""
  help
  exit 1
fi

echo "$bold*** memcached w/ persistence ***$normal"
echo "Using $bold$($MEMCACHE_BINARY --version | head -n1)$normal (at $MEMCACHE_BINARY)"
echo " - state file: $MEMCACHE_PERSISTENCE_STATE_FILE"
echo " - memfs file: $MEMCACHE_PERSISTENCE_MEMFS_FILE"

if ! [ -d "$MEMCACHE_PERSISTENCE_STATE_DIR" ]; then
  echo "ERROR: Persistent state directory $MEMCACHE_PERSISTENCE_STATE_DIR must already exist."
  exit 1
fi

if ! [ -d "$MEMCACHE_PERSISTENCE_MEMFS_DIR" ]; then
  echo "ERROR: Memory-based state directory $MEMCACHE_PERSISTENCE_MEMFS_DIR must already exist."
  exit 1
fi

if [ -f "$MEMCACHE_PERSISTENCE_STATE_FILE" ] && [ -f "$MEMCACHE_PERSISTENCE_STATE_FILE.meta" ]; then
  echo "Moving preexisting cache from persistent storage to memory-based storage..."
  mv -fv "$MEMCACHE_PERSISTENCE_STATE_FILE"       "$MEMCACHE_PERSISTENCE_MEMFS_FILE"
  mv -fv "$MEMCACHE_PERSISTENCE_STATE_FILE.meta"  "$MEMCACHE_PERSISTENCE_MEMFS_FILE.meta"
else
  echo "No preexisting cache file"
fi
echo ""

echo "$bold*** Starting Memcache... ***$normal"
memcached \
  "--memory-file=$MEMCACHE_PERSISTENCE_MEMFS_FILE" \
  "--extended=modern" \
  "--memory-limit=$MEMCACHE_CACHE_SIZE_MB" \
  "--max-item-size=$MEMCACHE_ITEM_SIZE" \
  "--lock-memory"
echo ""

echo "$bold*** Shutdown hook ***$normal"
if [ -f "$MEMCACHE_PERSISTENCE_STATE_FILE" ] && [ -f "$MEMCACHE_PERSISTENCE_STATE_FILE.meta" ]; then
  echo "INFO: Copying preexisting cache from persistent storage to memory-based storage..."
  mv -fv "$MEMCACHE_PERSISTENCE_MEMFS_FILE"       "$MEMCACHE_PERSISTENCE_STATE_FILE"
  mv -fv "$MEMCACHE_PERSISTENCE_MEMFS_FILE.meta"  "$MEMCACHE_PERSISTENCE_MEMFS_FILE.meta"
else
  echo "WARNING: No memory-based cache file found to copy to persistent storage. Skipping."
fi
