#!/bin/zsh
# Writes HomePad/Settings.bundle from the setting descriptors in the feature packages.
# Usage: Scripts/generate-settings.sh [--check]
set -euo pipefail

root="${0:A:h:h}"
cd "$root/Packages/HomePadSettingsCatalog"
export HOMEPAD_HOST_TESTS=1
exec nice -n 10 swift run -j 3 --scratch-path "$root/build/spm/HomePadSettingsCatalog" \
  homepad-settings "$root/HomePad/Settings.bundle" "$@"
