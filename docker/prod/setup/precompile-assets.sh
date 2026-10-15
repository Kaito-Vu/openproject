#!/bin/bash
set -euxo pipefail

DOCKER=${DOCKER:-0}

if [ -f config/frontend_assets.manifest.json ]; then
  echo "Assets have already been precompiled. Reusing."
else
  echo "Assets need to be compiled"
  JOBS=8 npm install

  SECRET_KEY_BASE="$(openssl rand -hex 64)" RAILS_ENV=production DATABASE_URL=nulldb://db \
    bin/rails openproject:plugins:register_frontend assets:precompile

  if [ "$DOCKER" = "1" ]; then
    rm -rf /tmp/nulldb
    # Remove sprockets cache
    rm -rf "$APP_PATH/tmp/cache/assets"
    # Remove node_modules and entire frontend
    rm -rf "$APP_PATH/node_modules/" "$APP_PATH/frontend/node_modules/"
    # Remove angular files, but leave the BuildKit cache mount (.angular/cache) alone
    find "$APP_PATH/frontend/.angular" -mindepth 1 -maxdepth 1 ! -name cache -exec rm -rf {} + 2>/dev/null || true
    rm -f "$APP_PATH/log/production.log"
  fi
fi