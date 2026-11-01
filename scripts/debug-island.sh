#!/usr/bin/env bash
# Development aid (debug builds only): expand the island to a page, or collapse it.
#   scripts/debug-island.sh expand media
#   scripts/debug-island.sh collapse
set -euo pipefail
action="${1:?usage: $0 expand <page>|collapse}"
page="${2:-}"
osascript -l JavaScript -e "
ObjC.import('Foundation');
\$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately(
  'io.github.islandbar.debug.${action}', '${page}' || \$(), \$(), true);" >/dev/null
