#!/usr/bin/env bash

set -euo pipefail

SCRIPTDIR="$(dirname "$0")"
source "$SCRIPTDIR/lib.sh"

CONFIG_TEMPLATE="${1:-${CONFIG_TEMPLATE:-"/config/config.tpl.json"}}"
CONFIG_OUTPUT="${CONFIG_OUTPUT:-"/config/config.json"}"
WATCH_INTERVAL_SECONDS="${WATCH_INTERVAL_SECONDS:-5}"

echo "----------------------------------"
echo "| mcrouter config watcher v0.0.1 |"
echo "----------------------------------"
echo "template: ${CONFIG_TEMPLATE}"
echo "  output: ${CONFIG_OUTPUT}"
echo "interval: ${WATCH_INTERVAL_SECONDS}"
echo ""

if ! [ -f "${CONFIG_TEMPLATE}" ]; then
  echo "Configuration template file ${CONFIG_TEMPLATE} not found"
  exit 1
fi

echo "Configuration template"
echo "----------------------------------"
cat "$CONFIG_TEMPLATE"
echo ""

if ! jq . "${CONFIG_TEMPLATE}" >/dev/null; then
  echo "Configuration template file is not valid Json."
  exit 1
fi

while true; do
  echo "Refreshing mcrouter configuration..."
  workdir="$(mktemp -d)"
  conf_epoch_file="$workdir/config.json"
  cp "$CONFIG_TEMPLATE" "$conf_epoch_file"

  if ! template_clusters_raw=$(jq -r ".pools[].servers[]" "${CONFIG_TEMPLATE}" | sort -u | grep -Ei '^dnssrv\:') >/dev/null; then
    echo "Unable to resolve the list of clusters used by the configuration template... Retrying in ${WATCH_INTERVAL_SECONDS}s..."
    sleep "${WATCH_INTERVAL_SECONDS}"
    continue
  fi

  template_clusters=()
  for template_cluster_rline in $template_clusters_raw; do
    template_cluster="${template_cluster_rline/dnssrv:/}"
    echo "+ queued $template_cluster"
    template_clusters+=("$template_cluster")
  done

  # if one cluster cannot be resolved, do not continue, but also don't just crash the pod
  # instead, we just try again in the next round
  successful_lookups="true"

  i=1
  ilen=${#template_clusters[@]}
  for cluster_dnssrv in "${template_clusters[@]}"; do
    cluster_file="$(mktemp -p "$workdir")"
    echo "===== [$i/$ilen] - Processing $cluster_dnssrv... ====="
    if ! cluster_info_lookup=$(resolve_cluster_pods_to "$cluster_dnssrv" "$cluster_file"); then
      echo "$cluster_info_lookup"
      successful_lookups="false"
    else
      echo "Resolved cluster pods!"
      pools_with_cluster=$(jq -r ".pools | to_entries[] | select(.value.servers == [ \"dnssrv:\"$cluster_dnssrv ]) | .key")
      for pool in $pools_with_cluster; do
        if ! jq_i ".pools.$pool = $(cat "$cluster_file")" "$conf_epoch_file"; then
          successful_lookups="false"
        fi
      done
    fi
    echo ""
    i=$(( i+1 ))
  done

  if [ "$successful_lookups" == "true" ]; then
    if are_different "$CONFIG_OUTPUT" "$conf_epoch_file"; then
      if [ -f "$CONFIG_OUTPUT" ]; then
        echo "Changes detected, updating live configuration..."
        diff --color "$CONFIG_OUTPUT" "$conf_epoch_file"
      else
        echo "New configuration generated:"
        cat "$conf_epoch_file"
      fi
      mv -fv "$conf_epoch_file" "$CONFIG_OUTPUT"
    else
      echo "Configuration unchanged"
    fi
  else
    echo "Errors while processing, aborting."
  fi
  echo ""

  rm -rf "$workdir"
  sleep "${WATCH_INTERVAL_SECONDS}"
done
