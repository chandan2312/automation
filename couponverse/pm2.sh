source ./couponasion.sh

key=1
key_range=5

for script in "${scripts[@]}"; do
    set -- $script
    script_path=$1
    name=$2
    country=$3
    iter=$4

    while true; do
        pm2 start /var/www/dc_factory/xvfb.sh --name "$name" -- /var/www/dc_factory/$script_path $country "$iter" "$key" --interpreter /bin/bash
        pm2 wait "$name"

        # Check the last 15 lines of the logs for "Ended successfully"
        log_output=$(pm2 logs "$name" --lines 15)
        if echo "$log_output" | grep -q "Ended successfully"; then
            echo "$name completed successfully"
            break  # Exit the while loop and move to the next script
        else
            error_message=$(echo "$log_output" | grep -E "${error_messages["too_many_requests"]}|${error_messages["navigation_error"]}|${error_messages["partial_translation"]}")

            if echo "$error_message" | grep -q "${error_messages["too_many_requests"]}"; then
                echo "$name $country $iter $key - 🗝️ key error 🗝️"
                echo "Error : $error_message"
                key=$((key % key_range + 1))
            elif echo "$error_message" | grep -q "${error_messages["navigation_error"]}\|${error_messages["partial_translation"]}"; then
                echo "$name $country $iter $key - ⏭️ skip error ⏭️"
                echo "Error : $error_message"
                iter=$((iter + 1))
            else
                echo "$name $country $iter $key - ⚠️ unknown error ⚠️"
                echo "Error : $error_message"
                iter=$((iter + 1))
            fi

            pm2 delete "$name"
            echo "Restarting $name $country $iter $key"
        fi
        sleep 5
    done
done
