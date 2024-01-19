#!/bin/bash
## Usage: key_value_reporter.sh input_file.txt
##
## This should be run on the output of consuming the kafka connect-configs topic.
## It will return the connectors that have been created and highlight any recent changes that have not been compacted
## kafka-console-consumer --bootstrap-server broker:9092 -topic connect-configs --from-beginning --property print.key=true
## Created by Conan Goldsmith, Last revised Jan 19th 2024

declare -A data
declare -A output

IFS=$' \t'
while IFS= read -r line; do
    line=$(echo "$line" | awk '{$1=$1};1')
    key=$(echo $line | awk '{print $1}' | sed 's/"//g')
    var=${line#* }
    value=$(echo $var | tr -d ' ')

    ignored_keys=("task-", "session-key", "commit-", "target-state-")

    for ik in "${ignored_keys[@]}"; do
        if [[ $key =~ $ik* || $key == $ik ]]; then
            continue 2  # skip this iteration if any ignored_key is a prefix of the key
        fi
    done

    # Parse JSON value into an associative array
    declare -A value_dict
    if [[ "$value" == "null" ]]; then
        output[$key]+=$'\n'"Connector \e[31m$key\e[0m deleted"$'\n'
	data_dict=()
        continue
    else
        value_dict=$(echo "$value" | jq -r 'to_entries')
    fi

    # Store value for next iteration
    data_dict=("${!value_dict[@]}")
    prev_value=${data[$key]}
    data[$key]=$value

    # Store changes for output
    if [[ ${output[$key]+_} ]]; then
        # Duplicate key found
        if [[ "$prev_value" == "null" ]]; then
            output[$key]+=$'\n'"Connector \e[31m$key\e[0m deleted"$'\n'
	else
            # Compare values
            output[$key]+=$'\n'"Connector \e[32m$key\e[0m updated"$'\n'
            for k in "${!value_dict[@]}"; do
                if [[ "${value_dict[$k]}" == "" || "${value_dict[$k]}" != "${value_dict[$k-1]}" ]]; then
                    if [[ "${value_dict[$k]}" == "" ]]; then
                        output[$key]+=$'\e[32m+'${value_dict[$k]}$'\e[0m\n'
                    else
			#prev_val=$(echo "${value_dict[$k-1]}" | jq -r --arg k "$k" '.[$k]' | tr -d '\n' | tr -d '\r' | tr -d '\t')
                        #curr_val=$(echo "${value_dict[$k]}" | tr -d '\n' | tr -d '\r' | tr -d '\t')
			# TODO Have it only highlight the specific lines that changed
			#prev_val_dict=$(echo "${value_dict[$k]}" | jq -r 'to_entries')
			#for ln in "${!prev_val[@]}"; do
			#	echo "LINE FOUND: ${prev_val[ln]}"
			#done
                        #if [[ "$prev_val" != "$curr_val" ]]; then
                           output[$key]+=$'\e[32m'"${value_dict[$k]}"$'\e[0m\n'
                        #else
                        #    output[$key]+="${value_dict[$k]}"$'\n'
                    #fi
                fi
	      fi
	    done
            for k in "${!value_dict[@]}"; do
                if [[ "${value_dict[$k]}" == "" ]]; then
                    output[$key]+=$'\e[31m-'${value_dict[$k]}$'\e[0m\n'
                fi
            done
        fi
    else
        # New key
        if [[ "$value" == "null" ]]; then
            output[$key]=$'\n'"Connector \e[31m$key\e[0m deleted"$'\n'
        else
            output[$key]=$'\n'"Connector \e[32m$key\e[0m created"$'\n'
            for k in "${!value_dict[@]}"; do
                output[$key]+="${value_dict[$k]}"$'\n'
            done
        fi
    fi
done < "$1"

# Output all changes grouped by key
for key in "${!output[@]}"; do
    if [[ "${output[$key]}" != "" ]]; then
        echo -e "${output[$key]}"
        echo "===================================================="
    fi
done
