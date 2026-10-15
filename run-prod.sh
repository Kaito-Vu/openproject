#!/usr/bin/env bash
# Run the production stack on the server.
# Usage: ./run-prod.sh [up|down|restart|pull|load <tar>|logs|ps]   (default: up)
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env.production ] || { echo ".env.production not found - copy .env.production.example first." >&2; exit 1; }

dc() { docker compose --env-file .env.production -f docker-compose.production.yml "$@"; }

case "${1:-up}" in
  up)      dc up -d --no-build ;;   # uses loaded/pulled images, never builds on the server
  down)    dc down ;;
  restart) dc restart web worker cron ;;
  pull)    dc pull --ignore-buildable ;;
  load)    docker load -i "${2:?usage: $0 load <images.tar>}" ;;
  logs)    dc logs -f --tail=200 web worker ;;
  ps)      dc ps ;;
  *)       echo "Usage: $0 [up|down|restart|pull|load <tar>|logs|ps]" >&2; exit 1 ;;
esac
