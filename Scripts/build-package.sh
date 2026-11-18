#!/bin/zsh
# Builds a package for an iOS device (no signing). Usage: Scripts/build-package.sh <PackageName>
# Output goes to a log; the last lines and any errors are printed.
set -uo pipefail

root="${0:A:h:h}"
source "$root/Scripts/lib/lock.zsh"
homepad_lock "$root"
trap homepad_unlock EXIT
trap 'exit 130' INT TERM
package="${1:?package name}"
log="${TMPDIR:-/tmp}/homepad-build-$package.log"

cd "$root/Packages/$package"
nice -n 10 xcodebuild -scheme "$package" -destination 'generic/platform=iOS' \
  -derivedDataPath "$root/build/DerivedData-$package" -jobs 3 \
  CODE_SIGNING_ALLOWED=NO -quiet build > "$log" 2>&1
code=$?
grep -E "error:|warning: unre|BUILD" "$log" | cut -c1-400 | sort -u | head -60
echo "exit $code (full log: $log)"
exit $code
