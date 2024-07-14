#!/bin/bash

PM2_PATH=~/.nvm/versions/node/v22.2.0/bin/pm2

scripts=(
    "cron/network/promocodie.js promocodie_CZ cz 0"
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
        $PM2_PATH start /var/www/dc_factory/xvfb.sh --name "$name" -- /var/www/dc_factory/$script_path $country "$iter" "$key" --interpreter /bin/bash --no-autorestart

        # Output logs in the background
        $PM2_PATH logs "$name" &

        # Wait until the process is no longer running
        while true; do
            status=$($PM2_PATH describe "$name" | grep "status" | awk '{print $2}')
            if [ "$status" != "online" ]; then
                break
            fi
            sleep 2  # Check every 2 seconds
        done

        # Check the last 15 lines of the logs after the script has stopped
        log_output=$($PM2_PATH logs "$name" --lines 15)
        echo "$log_output"  # Output to console for immediate visibility

        if echo "$log_output" | grep -q "Ended successfully"; then
            echo "$name completed successfully"
            break  # Exit the while loop and move to the next script
        fi

        error_message=$(echo "$log_output" | grep -E "${error_messages["too_many_requests"]}|${error_messages["navigation_error"]}|${error_messages["partial_translation"]}")

        if echo "$error_message" | grep -q "${error_messages["too_many_requests"]}"; then
            echo "$name $country $iter $key - 🗝️ key error 🗝️"
            echo "Error : $error_message"
            key=$((key % key_range + 1))
        else
            echo "$name $country $iter $key - ⚠️ unknown error ⚠️"
            echo "Error : $error_message"
            iter=$((iter + 1))
        fi

        $PM2_PATH delete "$name"
        echo "Restarting $name $country $iter $key"
    done
done
