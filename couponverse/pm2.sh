#!/bin/bash

PM2_PATH=~/.nvm/versions/node/v22.2.0/bin/pm2
NVM_PATH=~/.nvm

scripts=(
    "cron/network/promocodie.js promocodie_CZ cz 1500"
    "cron/network/promocodie.js promocodie_DE de 0"
    "cron/network/promocodie.js promocodie_BR br 0"
)

key=1
key_range=5

for script in "${scripts[@]}"; do
    set -- $script
    script_path=$1
    name=$2
    country=$3
    iter=$4

    $PM2_PATH stop "$name"
    echo "Stopped $name"

    while true; do
        # Start the script
        $PM2_PATH start /var/www/dc_factory/xvfb.sh --name "$name" -- /var/www/dc_factory/$script_path $country "$iter" "$key" --no-autorestart

        # Monitor the process
        while true; do
            status=$($PM2_PATH describe "$name" | grep "status" | awk '{print $2}')
            echo "Current status of $name: $status"

            if [ "$status" != "online" ]; then
                log_output=$($PM2_PATH logs "$name" --lines 15)
                echo "$log_output"

                if echo "$log_output" | grep -qi "Script ended"; then
                    echo "$name completed successfully"
                    break 2  # Exit both loops and move to the next script
                fi

                if echo "$log_output" | grep -qi "too many requests"; then
                    echo "$name $country $iter $key - 🗝️ key error 🗝️"
                    key=$((key % key_range + 1))
                elif echo "$log_output" | grep -qi "Navigation timeout\|partial translation\|status code 500\|Fatal server\|Make sure an X server"; then
                    echo "$name $country $iter $key - ⏭️ ⏭️"
                    iter=$((iter + 1))
                else
                    echo "$name $country $iter $key - ⚠️ unknown error ⚠️"
                fi

                $PM2_PATH delete "$name"
                echo "Restarting $name with iter=$iter, key=$key"
                sleep 60  # Sleep only after status is not online
                break  # Exit inner loop to restart the script
            fi

            sleep 2  # Check every 2 seconds
        done
    done
done
