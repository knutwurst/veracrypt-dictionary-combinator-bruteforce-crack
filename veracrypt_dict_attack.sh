#!/bin/bash

# Configuration
VERACRYPT_PATH="/Applications/VeraCrypt.app/Contents/MacOS/VeraCrypt"
VOLUME_PATH="container.tc"
MOUNT_POINT="/Volumes/cracked"
WORDLIST="wordlist.txt"
MIN_COMBINATION_LENGTH=1
MAX_COMBINATION_LENGTH=3
REPEAT_SINGLE_WORD=0
MAX_PARALLEL_JOBS=4

# Initialize counters and flags
PASSWORD_FOUND=0
CURRENT_ATTEMPT=0

# Load wordlist into array
read_wordlist_into_array() {
    local i=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        WORDLIST_ARRAY[i]="$line"
        ((i++))
    done < "$WORDLIST"
    WORDLIST_COUNT=$i
}

# Initialize wordlist array
declare -a WORDLIST_ARRAY
read_wordlist_into_array

# Calculate total number of attempts for progress display
calculate_total_attempts() {
    local total=0
    if [ $REPEAT_SINGLE_WORD -eq 1 ]; then
        total=$(($WORDLIST_COUNT * ($MAX_COMBINATION_LENGTH - $MIN_COMBINATION_LENGTH + 1)))
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
            PASSWORD_FOUND=1
            echo "Password found: $password"
            pkill -P $$ # Kill all child processes of this script
        fi
    ) &
}

# Function to ensure we do not exceed MAX_PARALLEL_JOBS
check_jobs() {
    while [ $(jobs -p | wc -l) -ge "$MAX_PARALLEL_JOBS" ]; do
        sleep 1 # Simple delay to avoid overloading the CPU with checks
    done
}

# Recursive function to generate combinations and try them
generate_combinations() {
    local prefix="$1"
    local depth="$2"
    if [ "$depth" -eq 0 ]; then
        try_password "$prefix"
        check_jobs
        return
    fi
    if [ $REPEAT_SINGLE_WORD -eq 1 ]; then
        for word in "${WORDLIST_ARRAY[@]}"; do
            if [ $PASSWORD_FOUND -eq 1 ]; then break; fi
            generate_combinations "$word" $(($depth - 1))
        done
    else
        for word in "${WORDLIST_ARRAY[@]}"; do
            if [ $PASSWORD_FOUND -eq 1 ]; then break; fi
            generate_combinations "$prefix$word" $(($depth - 1))
        done
    fi
}

# Handle interrupt signal
interrupt_handler() {
    echo "Interrupt signal received. Exiting..."
    pkill -P $$ # Kill all child processes of this script
    exit 1
}

trap interrupt_handler SIGINT

# Main function to initiate brute-force attack
main() {
    echo "Starting brute-force attack with $TOTAL_ATTEMPTS possible combinations."
    for ((depth=MIN_COMBINATION_LENGTH; depth<=MAX_COMBINATION_LENGTH; depth++)); do
        generate_combinations "" $depth
    done
    wait # Wait for all background jobs to finish
    if [ $PASSWORD_FOUND -eq 0 ]; then
        echo "Password not found with the given combinations."
    fi
}

main
