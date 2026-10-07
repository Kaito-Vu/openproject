#!/usr/bin/env bash
# Wrapper for the production run stack. Usage: ./run-production.sh [up|down|restart|pull|ps|logs] [service...]
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env.production ] || { echo ".env.production not found (cp .env.production.example .env.production)" >&2; exit 1; }
dc() { docker compose --env-file .env.production -f docker-compose-run-production.yaml "$@"; }

cmd="${1:-up}"; [ $# -gt 0 ] && shift
case "$cmd" in
  up)      dc pull; dc up -d --remove-orphans "$@"; dc ps ;;
  down)    dc down "$@" ;;
  restart) dc up -d --force-recreate "$@"; dc ps ;;
  pull)    dc pull "$@" ;;
  ps)      dc ps ;;
  logs)    dc logs -f --tail=100 "$@" ;;
  *)       echo "Usage: $0 [up|down|restart|pull|ps|logs] [service...]" >&2; exit 1 ;;
esac
