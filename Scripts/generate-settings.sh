#!/bin/zsh
# Writes HomePad/Settings.bundle from the setting descriptors in the feature packages, or with
# --check verifies that the checked-in bundle matches them. Both run a test of
# HomePadSettingsCatalog on the iOS simulator, which can reach this Mac's files.
# Usage: Scripts/generate-settings.sh [--check] [simulator name]
set -uo pipefail

root="${0:A:h:h}"
source "$root/Scripts/lib/lock.zsh"
homepad_lock "$root"
trap homepad_unlock EXIT
trap 'exit 130' INT TERM
bundle="$root/HomePad/Settings.bundle"
tests="HomePadSettingsCatalogTests"

if [[ "${1:-}" == "--check" ]]; then
  shift
  "$root/Scripts/test-package.sh" HomePadSettingsCatalog "${1:-iPhone 18 Pro}" \
    "-only-testing:$tests/SettingsCatalogTests/checkedInBundle_whenCompared_thenMatchesTheCatalog()"
  code=$?
  (( code == 0 )) && echo "Settings bundle is current." || echo "Settings bundle check failed."
else
  # xcodebuild hands this to the test as HOMEPAD_SETTINGS_BUNDLE_DIR.
  TEST_RUNNER_HOMEPAD_SETTINGS_BUNDLE_DIR="$bundle" \
    "$root/Scripts/test-package.sh" HomePadSettingsCatalog "${1:-iPhone 18 Pro}" \
    "-only-testing:$tests/SettingsBundleGeneratorTests"
  code=$?
  (( code == 0 )) && echo "wrote $bundle" || echo "Settings bundle was not written."
fi
exit $code
