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
    currIter=$4
    prevIter=-1

    $PM2_PATH stop "$name"
    echo "Stopped $name"

    while true; do
        prevIter=$currIter
        # Start the script
        $PM2_PATH start /var/www/dc_factory/xvfb.sh --name "$name" -- /var/www/dc_factory/$script_path $country "$currIter" "$key" --no-autorestart 

        while [ "$prevIter" -eq "$currIter" ]; do
            sleep 10 
            status=$($PM2_PATH jlist | grep -Po '"name":"'$name'".*?"status":"\K(.*?)"')
            

            echo "Status $name: $status"
            echo "currIter: $currIter , prevIter: $prevIter"

            if [ "$status" != "online" ]; then
                log_output=$($PM2_PATH logs "$name" --lines 100)
                log_output_15=$($PM2_PATH logs "$name" --lines 15) 
                echo "$log_output_15"

                if echo "$log_output" | grep -qi "Script Ended"; then
                    echo "$name completed successfully"
                    break 2
                fi

                if echo "$log_output" | grep -qi "too many requests"; then
                    echo "$name $country $currIter $key - 🗝️ key error 🗝️"
                    key=$((key % key_range + 1))
                elif echo "$log_output" | grep -qi "Navigation timeout\|partial translation\|status code 500\|Fatal server\|Make sure an X server"; then
                   
                    # Extract the current iter from the logs
                    extracted_iter=$(echo "$log_output" | grep -oP 'current iter: \K\d+' | tail -n 1 | xargs)
                    echo "Extracted iter: $extracted_iter"
                    if [ -n "$extracted_iter" ]; then
                         currIter=$(($extracted_iter + 1))
                        
                    else
                        echo "iter not extracted"
                        currIter=$((currIter + 10))
                    fi
                else
                    extracted_iter=$(echo "$log_output" | grep -oP 'current iter: \K\d+' | tail -n 1 | xargs)                    echo "Extracted iter: $extracted_iter"
                    if [ -n "$extracted_iter" ]; then
                         currIter=$(($extracted_iter + 1))
                         
                    else
                        echo "iter not extracted"
                        currIter=$((currIter + 10))
                        
                    fi
                fi

                $PM2_PATH stop "$name"
                $PM2_PATH delete "$name"
                echo "Restarting $name with currIter=$currIter, key=$key"
                sleep 60 
                break
            fi
        done 

        echo "Sleeping 120 seconds before next script"
        sleep 120 
    done
done
