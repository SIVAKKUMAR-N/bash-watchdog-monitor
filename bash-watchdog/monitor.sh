#!/bin/env bash
#PURE BASH WATCHDOG
#It is a monitoring tool that monitor host and updates the status of the host in the log in realtime
#input hosts for this tools should be in config/services.conf

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
set -a
source .env
set +a
fi
#Check if ALERT_EMAIL is set, if not exit with an error message
if [[ -z "$ALERT_EMAIL" ]]; then
    echo "ALERT_EMAIL not set. Exiting."
    exit 1
fi
#Locking mechanism to prevent multiple instances of the script from running simultaneously
LOCK_FILE="/tmp/bash_watchdog.lock"

exec 200>"$LOCK_FILE"
flock -n 200 || {
    echo "Another instance is running. Exiting."
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#What it does:
#dirname "$0" → directory where script is located
#cd ... && pwd → converts to absolute path
#Stores it in SCRIPT_DIR

#config file location
CONFIG_FILE="$SCRIPT_DIR/services.conf"
LOG_FILE="$SCRIPT_DIR/monitor.log"
STATE_FILE="$SCRIPT_DIR/state.db"


get_previous_entry() {
    grep -E "^$1 " "$STATE_FILE" 2> /dev/null 
}


update_state() {
    service="$1"
    new_state="$2"
    new_failures="$3"
    # Remove old entry
    grep -v -E "^$service " "$STATE_FILE" 2>/dev/null > "$STATE_FILE.tmp"
    #  -v → invert match (exclude lines matching the pattern) simply means to exclude the line that matches the service name
    #  -E → extended regex (allows for more complex patterns)
    mv "$STATE_FILE.tmp" "$STATE_FILE"

    # Add updated entry
    echo "$service $new_state $new_failures" >> "$STATE_FILE"
}
#function to check the http service by sending a request to the url and checking the response code
check_http() {
    if [[ "$port" == "443" ]]; then
        protocol="https"
    else
        protocol="http"
    fi

    url="$protocol://$host:$port$path"

    code=$(curl -s -o /dev/null -w "%{http_code}" \
           --max-time 3 "$url")

    if [[ "$code" -ge 200 && "$code" -lt 400 ]]; then
        return 0
    else
        return 1
    fi
}

#while loop to read the services.conf file
while read -r line; do


   # to skip empty lines
   [[ -z $line ]] && continue 
   # to skip comments
   [[ $line =~ ^# ]] && continue
   # reading the services detail and separate it 
read -r name host port mode threshold path <<< "$line"

   entry=$(get_previous_entry "$name")
   #extract previous status and failure count from the entry
   previous_status=$(echo "$entry" | awk '{print $2}')
   failure_count=$(echo "$entry" | awk '{print $3}')

   #default values for previous status , path and failure count if not provided in the state file
   failure_count=${failure_count:-0}
   previous_status=${previous_status:-UP}
   path=${path:-/}

   #default values for threshold and mode if not provided in the config file
   threshold=${threshold:-3}
   mode=${mode:-tcp}
#determine the protocol based on the port number, if the port is 443 then it is https otherwise it is http
if [[ "$mode" == "http" ]]; then
        if check_http; then
            status="UP"
            failure_count=0
        else
            failure_count=$((failure_count + 1))
            if [[ $failure_count -ge $threshold ]]; then
            status="DOWN" 
            else
             status="$previous_status"
            fi
        fi
else
#checking if nc (netcat) available -v is for verify 
if command -v nc > /dev/null; then  #here we use > /dev/null to suppress the output of the command

#nc method
if  nc -z -w 2 "$host" "$port" > /dev/null 2>&1; then
      status="UP"
      failure_count=0
else
      failure_count=$((failure_count + 1))
      if [[ $failure_count -ge $threshold ]]; then
         status="DOWN" 
      else
         status="$previous_status"
      fi
      
fi

else
#bash TCP METHOD
if timeout 2 bash -c "</dev/tcp/$host/$port" > /dev/null 2>&1; then 
   status="UP"
   failure_count=0
else
   failure_count=$((failure_count + 1))
   if [[ $failure_count -ge $threshold ]]; then
      status="DOWN"
   else
      status="$previous_status"
   fi

fi
fi
fi
#check if the status has changed from previous status, if it has changed then log the new status and send an email alert
if [[ "$previous_status" != "$status" ]]; then
    {
        echo "$(date) $name $host $port $mode $threshold $path $status"
    } >> "$LOG_FILE" 2>>"$SCRIPT_DIR/error.log"

    subject="[WATCHDOG] $name is $status"

    body="Service: $name
Host: $host
Port: $port
Status: $status
Time: $(date)
"

    echo -e "Subject: $subject\n\n$body" | msmtp "$ALERT_EMAIL" \
        || echo "$(date) EMAIL FAILED for $name" >> "$SCRIPT_DIR/error.log"
fi

update_state "$name" "$status" "$failure_count"
done < "$CONFIG_FILE"                                    
