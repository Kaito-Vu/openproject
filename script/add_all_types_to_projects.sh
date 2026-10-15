#!/usr/bin/env bash
# Adds every work package type to every project via the OpenProject API.
# Usage: HOST=https://op.example.com KEY=<admin api key> [DRY_RUN=1] ./add_all_types_to_projects.sh
set -u
: "${HOST:?set HOST}" "${KEY:?set KEY}"
AUTH=(-u "apikey:$KEY")

# 1. types, fetched once
TYPE_IDS=$(curl -sf "${AUTH[@]}" "$HOST/api/v3/types" | jq -c '[._embedded.elements[].id]') \
  || { echo "failed to fetch types"; exit 1; }
echo "types: $TYPE_IDS"

# 2. projects, fetched once (all pages)
PROJECT_IDS=""
page=1
while :; do
  resp=$(curl -sf "${AUTH[@]}" "$HOST/api/v3/projects?pageSize=100&offset=$page") \
    || { echo "failed to fetch projects page $page"; exit 1; }
  ids=$(jq -r '._embedded.elements[].id' <<<"$resp")
  [ -z "$ids" ] && break
  PROJECT_IDS+="$ids"$'\n'
  [ "$(jq '.count' <<<"$resp")" -lt 100 ] && break
  page=$((page + 1))
done
echo "projects: $(grep -c . <<<"$PROJECT_IDS")"

# 3. per project: current types + all types -> PUT (replace semantics, so merge first)
ok=0; fail=0
while read -r PID; do
  [ -z "$PID" ] && continue
  BODY=$(curl -sf "${AUTH[@]}" "$HOST/api/v3/projects/$PID/types" \
    | jq -c --argjson all "$TYPE_IDS" \
      '[[._embedded.elements[].id] + $all | unique[] | {href: "/api/v3/types/\(.)"}] | {_links: {types: .}}')
  if [ -z "$BODY" ]; then echo "project $PID: cannot read current types"; fail=$((fail+1)); continue; fi
  if [ "${DRY_RUN:-0}" = 1 ]; then echo "project $PID: would PUT $BODY"; continue; fi
  CODE=$(curl -s -o /tmp/op_resp.json -w '%{http_code}' "${AUTH[@]}" -X PUT \
    -H 'Content-Type: application/json' -d "$BODY" "$HOST/api/v3/projects/$PID/types")
  if [ "$CODE" = 200 ]; then ok=$((ok+1)); echo "project $PID: ok"
  else fail=$((fail+1)); echo "project $PID: HTTP $CODE $(jq -r '.message // empty' /tmp/op_resp.json)"; fi
done <<<"$PROJECT_IDS"
echo "done: ok=$ok fail=$fail"
