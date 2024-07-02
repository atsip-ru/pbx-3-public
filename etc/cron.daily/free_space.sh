#!/bin/bash

# Set the maximum allowed disk space usage percentage
MAX=60

# Set the email address to receive alerts
EMAIL=""

tlgrm_id=""
bot_token=""
hostname=$(hostname)

# Set the partition to monitor (change accordingly, e.g., /dev/sda1)
PARTITION=/dev/sdb2

# Get the current disk usage percentage and related information
USAGE_INFO=$(df -h "$PARTITION" | awk 'NR==2 {print $5, $1, $2, $3, $4}' | tr '\n' ' ')
USAGE=$(echo "$USAGE_INFO" | awk '{print int($1)}') # Remove the percentage sign

if [ "$USAGE" -gt "$MAX" ]; then
    # Send an email alert with detailed disk usage information
    echo -e "Warning: Disk space usage on $PARTITION is $USAGE%.\n\nDisk Usage Information:\n$USAGE_INFO" | \
    curl -s -X POST https://api.telegram.org/${bot_token}/sendMessage -d parse_mode=html -d text="<b>${hostname}:</b> Disk Space Alert on $hostname" -d chat_id=${tlgrm_id}
    #mail -s "Disk Space Alert on $HOSTNAME" "$EMAIL"
fi
