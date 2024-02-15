#!/bin/bash

# Configuration
VERACRYPT_PATH="/Applications/VeraCrypt.app/Contents/MacOS/VeraCrypt"
VOLUME_PATH="container.tc"
MOUNT_POINT="/Volumes/cracked"
WORDLIST="wordlist.txt"
MIN_COMBINATION_LENGTH=1
MAX_COMBINATION_LENGTH=4
REPEAT_SINGLE_WORD=0
MAX_PARALLEL_JOBS=8
PASSWORD_FOUND_FILE="password_found"

# Initialize
CURRENT_ATTEMPT=0

# Clean up the signal file at the start
rm -f "$PASSWORD_FOUND_FILE"

# Load wordlist into array
read_wordlist_into_array() {
    local i=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        WORDLIST_ARRAY[i]="$line"
        ((i++))
    done < "$WORDLIST"
    WORDLIST_COUNT=$i
}

declare -a WORDLIST_ARRAY
read_wordlist_into_array

calculate_total_attempts() {
    local total=0
    if [ $REPEAT_SINGLE_WORD -eq 1 ]; then
        total=$((WORDLIST_COUNT * (MAX_COMBINATION_LENGTH - MIN_COMBINATION_LENGTH + 1)))
    else
        for ((depth=MIN_COMBINATION_LENGTH; depth<=MAX_COMBINATION_LENGTH; depth++)); do
            total=$(($total + ${#WORDLIST_ARRAY[@]} ** depth))
        done
    fi
    echo $total
}

TOTAL_ATTEMPTS=$(calculate_total_attempts)

# Function to try passwords in parallel
try_password() {
    local password="$1"
    ((CURRENT_ATTEMPT++))
    echo "Attempt $CURRENT_ATTEMPT of $TOTAL_ATTEMPTS: Trying password '$password'"
    (
        if "$VERACRYPT_PATH" --text --non-interactive --password="$password" "$VOLUME_PATH" "$MOUNT_POINT" &>/dev/null; then
            echo "Password found: $password"
            touch "$PASSWORD_FOUND_FILE"
            exit 0
        fi
    ) &
    PID=$!
    echo "Launched VeraCrypt attempt with PID: $PID"
}

# Check for the temporary file indicating the password was found
check_password_found() {
    if [ -f "$PASSWORD_FOUND_FILE" ]; then
        echo "Password found, stopping attempts..."
        return 0 # Password found
    fi
    return 1 # Password not found
}

# Function to ensure we do not exceed MAX_PARALLEL_JOBS
check_jobs() {
    while [ $(jobs -p | wc -l) -ge "$MAX_PARALLEL_JOBS" ]; do
        sleep 1
        check_password_found && pkill -P $$ && break
    done
}

generate_combinations() {
    local prefix="$1"
    local depth="$2"
    if [ "$depth" -eq 0 ]; then
        try_password "$prefix"
        check_jobs
        check_password_found && return
        return
    fi
    for word in "${WORDLIST_ARRAY[@]}"; do
        generate_combinations "$prefix$word" $(($depth - 1))
        check_password_found && break
    done
}

# Handle interrupt signal
interrupt_handler() {
    echo "Interrupt signal received. Cleaning up..."
    rm -f "$PASSWORD_FOUND_FILE"
    pkill -P $$
    exit 1
}

trap interrupt_handler SIGINT

# Main function to initiate brute-force attack
main() {
    echo "Starting brute-force attack with $TOTAL_ATTEMPTS possible combinations."
    for ((depth=MIN_COMBINATION_LENGTH; depth<=MAX_COMBINATION_LENGTH; depth++)); do
        generate_combinations "" $depth
        check_password_found && echo "Stopping further attempts." && break
    done
    wait # Wait for all background jobs to finish
    if [ -f "$PASSWORD_FOUND_FILE" ]; then
        echo "Password successfully found."
    else
        echo "Password not found with the given combinations."
    fi
    rm -f "$PASSWORD_FOUND_FILE"
}

main
