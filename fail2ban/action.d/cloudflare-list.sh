#!/bin/bash

# Performs addition or deletion of an IP in a Cloudflare custom list.
# Support for IPv6 is limited as it blocks the entire /64 subnet.

# === Cloudflare API Credentials ===
# These values are specific to your Cloudflare account and list.
# Your Cloudflare account ID
accountId="xxxxx"
# ID of the Cloudflare custom list
listId="xxxxx"
# Cloudflare API token or key
apiToken="xxxx"  
# === End Cloudflare API Credentials ===

# Exit on any error
set -e

# Function to print usage and exit
usage() {
    echo "Usage: $0 <ip> <add|del>"
    exit 1
}

# Function to validate IP address (basic check)
validate_ip() {
    local ip=$1
    # Basic IPv4/IPv6 regex (not exhaustive, but sufficient for most cases)
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || $ip =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    else
        echo "Error: Invalid IP address: $ip"
        exit 1
    fi
}

# Function to normalize IPv6 to /64 subnet
normalize_ipv6() {
    local ip=$1
    # Check if it's an IPv6 address (contains colons)
    if [[ $ip =~ : ]]; then
        # Expand IPv6 address (e.g., 2001:db8::1 -> 2001:0db8:0000:0000:0000:0000:0000:0001)
        # This is a simplified approach; for full accuracy, use a tool like sipcalc
        local expanded=""
        local parts
        IFS=':' read -r -a parts <<< "$ip"
        local count=${#parts[@]}
        local i
        for ((i=0; i<8; i++)); do
            if [[ $i -lt $count && -n ${parts[$i]} ]]; then
                expanded+=$(printf "%04x" 0x${parts[$i]})
            else
                expanded+="0000"
            fi
            [[ $i -lt 7 ]] && expanded+=":"
        done
        # Take first 4 segments (64 bits) and append ::/64
        local first_64
        first_64=$(echo "$expanded" | cut -d':' -f1-4)
        echo "${first_64}::/64"
    else
        echo "$ip"
    fi
}

# Function to get existing IP list from Cloudflare
get_ip_list() {
    local endpoint=$1
    local headers=(
        -H "Authorization: Bearer $apiToken"
        -H "Content-Type: application/json"
    )
    response=$(curl -s -w "\n%{http_code}" "$endpoint" "${headers[@]}")
    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n -1)
    if [[ $status_code -eq 200 ]]; then
        echo "$body"
    else
        echo "Failed to fetch existing IP list. Status code: $status_code"
        echo "$body"
        exit 1
    fi
}

# Function to add IP to Cloudflare list
add_ip_to_list() {
    local ip=$1 endpoint=$2
    local headers=(
        -H "Authorization: Bearer $apiToken"
        -H "Content-Type: application/json"
    )
    local payload='[{"ip": "'"$ip"'"}]'
    response=$(curl -s -w "\n%{http_code}" -X POST "$endpoint" "${headers[@]}" -d "$payload")
    echo "$response"
}

# Function to remove IP from Cloudflare list
remove_ip_from_list() {
    local ip_id=$1 endpoint=$2
    local headers=(
        -H "Authorization: Bearer $apiToken"
        -H "Content-Type: application/json"
    )
    local payload='{"items": [{"id": "'"$ip_id"'"}]}'
    response=$(curl -s -w "\n%{http_code}" -X DELETE "$endpoint" "${headers[@]}" -d "$payload")
    echo "$response"
}

# Main script
# Check arguments
if [[ $# -lt 2 ]]; then
    usage
fi

ipAddr=$1
action=$2
apiEndpoint="https://api.cloudflare.com/client/v4/accounts/$accountId/rules/lists/$listId/items"

# Validate IP
validate_ip "$ipAddr"

# Normalize IPv6 if applicable (disable by setting CF_USE_IPV6_CIDR=false)
if [[ "${CF_USE_IPV6_CIDR:-true}" == "true" ]]; then
    ipAddr=$(normalize_ipv6 "$ipAddr")
fi

# Validate action
if [[ "$action" != "add" && "$action" != "del" ]]; then
    echo "Error: Action must be 'add' or 'del'"
    exit 1
fi

# Get existing IP list
existingIpList=$(get_ip_list "$apiEndpoint")
# Debugging: Print the list (optional, comment out in production)
# echo "$existingIpList"

response=""
if [[ "$action" == "del" ]]; then
    # Find IP ID
    ipId=$(echo "$existingIpList" | jq -r '.result[] | select(.ip == "'"$ipAddr"'") | .id')
    if [[ -n "$ipId" ]]; then
        response=$(remove_ip_from_list "$ipId" "$apiEndpoint")
    else
        echo "IP address $ipAddr not found in the custom IP list."
        exit 1
    fi
elif ! echo "$existingIpList" | jq -e '.result[] | select(.ip == "'"$ipAddr"'")' >/dev/null; then
    # Add IP only if it doesn't exist
    response=$(add_ip_to_list "$ipAddr" "$apiEndpoint")
else
    echo "IP address $ipAddr already exists in the custom IP list."
    exit 0
fi

# Process response
if [[ -n "$response" ]]; then
    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n -1)
    if [[ $status_code -eq 200 ]]; then
        echo "IP address $ipAddr $action to the custom IP list successfully."
    else
        echo "Failed to $action IP address $ipAddr to the custom IP list. Status code: $status_code"
        echo "Response: $body"
        exit 1
    fi
else
    echo "Failed to $action IP address $ipAddr to the custom IP list. No response received."
    exit 1
fi
