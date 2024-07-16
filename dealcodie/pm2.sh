#!/bin/bash

PM2_PATH=~/.nvm/versions/node/v22.2.0/bin/pm2
NVM_PATH=~/.nvm

if [ $# -ne 3 ]; then
    echo "Usage: $0 <script_array_file> <start_index> <initial_iter>"
    exit 1
fi

SCRIPT_ARRAY_FILE=$1
START_INDEX=$2
INITIAL_ITER=$3

# Source the script array file
if [ -f "$SCRIPT_ARRAY_FILE" ]; then
    source "$SCRIPT_ARRAY_FILE"
else
    echo "File $SCRIPT_ARRAY_FILE not found."
    exit 1
fi

# Validate START_INDEX
if ! [[ "$START_INDEX" =~ ^[0-9]+$ ]]; then
    echo "Start index must be a non-negative integer."
    exit 1
fi

# Validate INITIAL_ITER
if ! [[ "$INITIAL_ITER" =~ ^[0-9]+$ ]]; then
    echo "Initial iteration must be a non-negative integer."
    exit 1
fi

key=1
key_range=5

# Loop through the scripts array starting from the given index
for ((i=START_INDEX; i<${#scripts[@]}; i++)); do
    script="${scripts[$i]}"
    set -- $script
    script_path=$1
    name=$2
    country=$3
    if [ $i -eq $START_INDEX ]; then
        currIter=$INITIAL_ITER
    else
        currIter=$4
    fi
    prevIter=-1

    $PM2_PATH stop "$name"
    echo "Stopped $name"

    while true; do
        # Start the script
        $PM2_PATH start /var/www/dc_factory/xvfb.sh --name "$name" --no-autorestart -- /var/www/dc_factory/$script_path $country "$currIter" "$key"

        while true; do
            status=$($PM2_PATH jlist | grep -Po '"name":"'$name'".*?"status":"\K[^"]*' | xargs)
            current_time=$(date +"%Y-%m-%d %H:%M:%S")

            if [ "$status" == "online" ]; then
                sleep 120
            else
                echo "$status - $current_time"

                log_output=$(cat "/root/.pm2/logs/$name-out.log" | tail -n 30)
                sleep 5
                log_output_5=$(cat "/root/.pm2/logs/$name-out.log" | tail -n 5)
                echo "$log_output_5"

                if echo "$log_output" | grep -qi "Script Ended"; then
                    echo "$name completed successfully"
                    $PM2_PATH delete "$name"
                    sleep 10
                    break 2
                fi

                if echo "$log_output" | grep -qi "too many requests\|Resource exhausted\|was blocked\|Request failed with status code 429\|Gemini Block Error"; then
                    echo "$name $country $currIter $key - 🗝️ key error 🗝️"
                    key=$((key % key_range + 1))
                    extracted_iter=$(echo "$log_output" | grep -oP 'current iter: \K\d+' | tail -n 1 | xargs)
                    echo "Extracted iter: $extracted_iter"
                    if [ -n "$extracted_iter" ]; then
                        currIter=$((extracted_iter))
                    else
                        echo "iter not extracted"
                        currIter=$((currIter + 10))
                    fi

                elif echo "$log_output" | grep -qi "Navigation timeout\|Partial Translation\|status code 500\|Fatal server\|Make sure an X server"; then
                    extracted_iter=$(echo "$log_output" | grep -oP 'current iter: \K\d+' | tail -n 1 | xargs)
                    echo "Extracted iter: $extracted_iter"

                    if [ -n "$extracted_iter" ]; then
                        currIter=$((extracted_iter + 1))
                    else
                        echo "iter not extracted"
                        currIter=$((currIter + 10))
                    fi
                else
                    extracted_iter=$(echo "$log_output" | grep -oP 'current iter: \K\d+' | tail -n 1 | xargs)
                    echo "Extracted iter: $extracted_iter"

                    if [ -n "$extracted_iter" ]; then
                        currIter=$((extracted_iter + 1))
                    else
                        echo "iter not extracted"
                        currIter=$((currIter + 10))
                    fi
                fi

                sleep 5
                break
            fi
        done

        sleep 30
        echo "Restarting $name with currIter=$currIter, key=$key"
    done
done
