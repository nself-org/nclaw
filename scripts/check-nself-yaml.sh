#!/usr/bin/env bash
# Purpose: offline guard for an app repo's nself.yaml (P7-TRUTH config contract).
# Usage:   bash scripts/check-nself-yaml.sh FILE
# Exit 0:  FILE declares a top-level cli_min_version and every top-level key is
#          one the nself CLI reads (app, cli_min_version, bundle, bundles,
#          plugins) or an x- extension key. Exit 1 otherwise; exit 2 on usage.
# Constraints: bash 3.2, no network, no yaml parser; top-level keys only (the
#          nested shapes are checked by `nself config validate`).
# SPORT: contract:config.nself-yaml

set -u

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "usage: check-nself-yaml.sh FILE (nself.yaml)" >&2
  exit 2
fi

rc=0
found_min=0
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  case "$line" in
    '' | '#'* | ' '* | "$(printf '\t')"* | '-'* | '...') continue ;;
  esac
  key="${line%%:*}"
  [ "$key" = "$line" ] && continue # not a mapping line
  key="${key%\"}"
  key="${key#\"}"
  key="${key%\'}"
  key="${key#\'}"
  case "$key" in
    cli_min_version) found_min=1 ;;
    app | bundle | bundles | plugins) ;;
    x-*) ;;
    *)
      echo "$FILE:$lineno: top-level key '$key' is not read by the nself CLI; rename it to 'x-$key'" >&2
      rc=1
      ;;
  esac
done <"$FILE"

if [ "$found_min" -ne 1 ]; then
  echo "$FILE: missing top-level cli_min_version" >&2
  rc=1
fi
exit "$rc"
