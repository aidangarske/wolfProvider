#!/bin/bash
# This script provides the bare minimum function definitions for compiling
# the wolfProvider library

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ "$UTILS_GENERAL_LOADED" != "yes" ]; then # only set once
    kill_servers() {
        if [ "$(jobs -p)" != "" ]; then
            kill $(jobs -p)
        fi
    }

    do_cleanup() {
        sleep 0.5 # flush buffers
        kill_servers
    }

    do_trap() {
        printf "got trap\n"
        do_cleanup
        date
        exit 1
    }
    trap do_trap INT TERM

    export UTILS_GENERAL_LOADED=yes
fi

check_folder_age() {
    folderA=$1
    folderB=$2

    if [[ "$OSTYPE" == "darwin"* ]]; then
        folderA_age=$(find "$folderA" -type f -exec stat -f '%Dm' {} \; | sort -n | tail -n 1)
        folderB_age=$(find "$folderB" -type f -exec stat -f '%Dm' {} \; | sort -n | tail -n 1)
    else
        folderA_age=$(find "$folderA" -type f -printf '%T@' | sort -n | tail -n 1)
        folderB_age=$(find "$folderB" -type f -printf '%T@' | sort -n | tail -n 1)
    fi

    if awk "BEGIN {exit !($folderA_age > $folderB_age)}"; then
        echo 1
    elif awk "BEGIN {exit !($folderA_age < $folderB_age)}"; then
        echo -1
    else
        echo 0
    fi
}

clean_rebuild() {
    # Function to completely clean all build artifacts and source directories
    # Usage: clean_rebuild [--force] [--keep-sources]
    #   --force: Skip confirmation prompt
    #   --keep-sources: Keep source directories, only remove install directories
    
    local force=0
    local keep_sources=0
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=1
                shift
                ;;
            --keep-sources)
                keep_sources=1
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: clean_rebuild [--force] [--keep-sources]"
                return 1
                ;;
        esac
    done
    
    # Define directories to clean
    local install_dirs=(
        "${SCRIPT_DIR}/../openssl-install"
        "${SCRIPT_DIR}/../wolfssl-install" 
        "${SCRIPT_DIR}/../wolfprov-install"
    )
    
    local source_dirs=(
        "${SCRIPT_DIR}/../openssl-source"
        "${SCRIPT_DIR}/../wolfssl-source"
    )
    
    # Confirm unless --force is used
    if [ $force -eq 0 ]; then
        read -p "Clean rebuild? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    # Remove install directories
    for dir in "${install_dirs[@]}"; do
        [ -d "$dir" ] && rm -rf "$dir"
    done
    
    # Handle source directories
    if [ $keep_sources -eq 0 ]; then
        # Remove source directories completely
        for dir in "${source_dirs[@]}"; do
            [ -d "$dir" ] && rm -rf "$dir"
        done
    else
        # Clean source directories with git clean
        for dir in "${source_dirs[@]}"; do
            if [ -d "$dir" ] && [ -d "$dir/.git" ]; then
                pushd "$dir" > /dev/null
                git clean -xdf > /dev/null 2>&1
                popd > /dev/null
            fi
        done
    fi
}

