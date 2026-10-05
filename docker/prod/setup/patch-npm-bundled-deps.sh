#!/bin/bash
set -euxo pipefail

# The npm CLI vendors its own dependencies under /usr/local/lib/node_modules/npm/node_modules.
# Two of them are vulnerable and no released npm bundles the fixes yet:
#   CVE-2026-69192  ip-address       fixed in 10.3.1
#   CVE-2026-14257  brace-expansion  fixed in 5.0.8
#   CVE-2026-102276 brace-expansion  fixed in 5.0.10
#   CVE-2026-102278 brace-expansion  fixed in 5.0.11
# Replace the bundled copies with patched versions. Runs in a throwaway directory so npm does
# not try to reconcile the npm CLI's own manifest.
NPM_BUNDLED=/usr/local/lib/node_modules/npm/node_modules

if [ ! -d "$NPM_BUNDLED" ]; then
  echo "npm is not installed in this stage, skipping the bundled dependency patch"
  exit 0
fi

tmp_dir=$(mktemp -d)
cd "$tmp_dir"
npm install --no-save --no-audit --no-fund ip-address@10.7.3 brace-expansion@5.0.12
for package in ip-address brace-expansion; do
  rm -rf "$NPM_BUNDLED/$package"
  cp -a "$tmp_dir/node_modules/$package" "$NPM_BUNDLED/$package"
done
cd /
rm -rf "$tmp_dir"

node -e "require('$NPM_BUNDLED/ip-address'); require('$NPM_BUNDLED/brace-expansion'); console.log('patched npm bundled dependencies')"
