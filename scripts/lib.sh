#!/usr/bin/env bash

set -euo pipefail

# minimal IP address regex
# not there for security but rather to catch severe DNS misconfigurations if they don't raise error codes
# from https://stackoverflow.com/a/36760050 with minimal replacements to support whatever stupid limitations afflict crusty grep setups
REGEX_IP4="^((25[0-5]|(2[0-4]|1[0-9]|[1-9]?)[0-9]\.){3}(25[0-5]|(2[0-4]|1[0-9]|[1-9]?)[0-9]))$"
# REGEX_IP6="lol good luck"

# in-place jq
function jq_i() {
  local command=$1
  local file=$2

  local tmpfile
  tmpfile=$(mktemp)

  if jq "$command" "$file" > "$tmpfile"; then
    mv -f "$tmpfile" "$file"
  else
    rm "$tmpfile"
    return 1
  fi
}

function resolve_cluster_pods_to() {
  local cluster_dnssrv=$1
  local destination_file=$2

  if [ -z "$cluster_dnssrv" ] || [ -z "$destination_file" ]; then
    help
  fi

  local srv_result
  if ! srv_result=$(dig +short "$cluster_dnssrv" SRV); then
    echo "Failed resolving SRV records for \"$cluster_dnssrv\" (dig(1) exit code $?)"
    exit 1
  fi

  if [ -z "$srv_result" ]; then
    echo "Empty response while looking up SRV records at \"$cluster_dnssrv\""
    exit 1
  fi

  # poor man's brittle-but-still-technically-consistent sorting
  srv_result=$(echo "$srv_result" | sort -n -k4)

  local pods_json=()
  while IFS= read -r line; do
    # extract pod-specific DNS A record
    if ! pod_a_record=$(echo "$line" | awk '{print $4}'); then
      echo "Failed extracting pod A record from SRV lookup response"
      exit 1
    fi
    echo "> Resolving pod A record \"$pod_a_record\""

    # grab the pod's name from the A record
    if ! pod_name=$(echo "$pod_a_record" | cut -d '.' -f1); then
      echo "Failed extracting pod's name from A record"
      exit 1
    fi

    # resolve the A record to get the relevant pod's cluster IP
    if ! pod_ip_lookup=$(dig +short "$pod_a_record"); then
      echo "Failed resolving pod cluster IP from its A record \"$pod_a_record\" (dig(1) exit code $?)"
      exit 1
    fi

    # extract IP from pod IP lookup
    if ! pod_ip=$(echo "$pod_ip_lookup" | grep -Eio "$REGEX_IP4"); then
      echo "Failed extracting pod IP address from A record response. Unexpected response format:"
      echo "$pod_ip_lookup"
      exit 1
    fi

    if ! pod_port=$(echo "$line" | cut -d ' ' -f3 | grep -Eio "^[1-9][0-9]*$"); then
      echo "Failed extracting pod service port from SRV lookup response. Unexpected response format:"
      echo "$line"
      exit 1
    fi

    echo "<+ name=\"$pod_name\""
    echo "   ip=\"$pod_ip\""
    echo "   port=$pod_port"

    pods_json+=("{ \"name\": \"$pod_name\", \"ip\": \"$pod_ip\", \"port\": $pod_port }")
  done <<< "$srv_result"

  echo ""
  echo "Found the following cluster pods:"

  i=1
  ilen=${#pods_json[@]}

  printf "[\n" | tee "$destination_file"
  for pod_json in "${pods_json[@]}"; do
    printf "  %s" "$pod_json" | tee -a "$destination_file"
    if [ "$i" != "$ilen" ]; then
      printf "," | tee -a "$destination_file"
    fi
    printf "\n" | tee -a "$destination_file"
    i=$(( i+1 ))
  done
  echo "]" | tee -a "$destination_file"
}

function are_different() {
  local a="$1"
  local b="$2"

  if ! [ -f "$a" ] && [ -f "$b" ]; then
    return 0
  elif [ -f "$a" ] && ! [ -f "$b" ]; then
    return 0
  fi

  if [ "$(sha256sum "$a" | cut -d ' ' -f1)" == "$(sha256sum "$b" | cut -d ' ' -f2)" ]; then
    return 0
  else
    return 1
  fi
}
