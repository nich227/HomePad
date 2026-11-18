#!/bin/zsh
# Builds the app for the iPad simulator. Usage: Scripts/build-app.sh [simulator name]
# Output goes to a log; errors and the result are printed.
set -uo pipefail

root="${0:A:h:h}"
device="${1:-iPad Pro 13-inch (M5)}"
log="${TMPDIR:-/tmp}/homepad-build-app.log"

cd "$root"
xcodegen generate --quiet || exit 1
nice -n 10 xcodebuild -project HomePad.xcodeproj -scheme HomePad -configuration Debug \
  -destination "platform=iOS Simulator,name=$device" \
  -derivedDataPath "$root/build/DerivedData-App" -jobs 4 -quiet build > "$log" 2>&1
code=$?
grep -E "error:|BUILD" "$log" | grep -v "failed with exit code 0" | cut -c1-400 | sort -u | head -60
echo "exit $code (full log: $log)"
exit $code
