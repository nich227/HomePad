#!/bin/zsh
# Runs the UI walkthrough on the iPad simulator and saves screenshots to design/screenshots.
# It shuts the simulator down afterwards.
# Usage: Scripts/ui-walkthrough.sh [simulator name]
set -uo pipefail

root="${0:A:h:h}"
device="${1:-iPad Pro 13-inch (M5)}"
log="${TMPDIR:-/tmp}/homepad-ui-walkthrough.log"

cd "$root"
xcodegen generate --quiet || exit 1
xcrun simctl uninstall booted com.kevster.HomePad >/dev/null 2>&1
export TEST_RUNNER_HOMEPAD_SCREENSHOT_DIR="$root/design/screenshots"
rm -rf "$root/build/ui-walkthrough.xcresult"
nice -n 10 xcodebuild -project HomePad.xcodeproj -scheme HomePad -configuration Debug \
  -destination "platform=iOS Simulator,name=$device" \
  -derivedDataPath "$root/build/DerivedData-App" -jobs 4 \
  -resultBundlePath "$root/build/ui-walkthrough.xcresult" test > "$log" 2>&1
code=$?
grep -E "error:|Test Case.*(passed|failed)|\*\* TEST" "$log" | cut -c1-300 | tail -20
xcrun simctl shutdown "$device" >/dev/null 2>&1
echo "exit $code (full log: $log)"
exit $code
