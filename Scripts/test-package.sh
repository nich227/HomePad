#!/bin/zsh
# Runs a package's unit tests on an iOS simulator with code coverage, then shuts the simulator down.
# Usage: Scripts/test-package.sh <PackageName> [simulator name] [extra xcodebuild arguments]
# The simulator defaults to "iPhone 18 Pro". Extra arguments go to xcodebuild as they are, for
# example -only-testing:<TestTarget>/<Suite>. xcodebuild hands every environment variable named
# TEST_RUNNER_<NAME> to the tests as <NAME>.
# Output goes to a log. The Swift Testing summary, any failures, the result line, and the line
# coverage of <PackageName>Core (or of the package's only target) are printed. A run narrowed with
# -only-testing or -skip-testing measures no coverage, because the number would mean nothing.
# Exits non-zero when the build or a test fails.
set -uo pipefail

root="${0:A:h:h}"
package="${1:?package name}"
device="${2:-iPhone 18 Pro}"
shift
(( $# > 0 )) && shift

derived="$root/build/DerivedData-$package"
result="$root/build/test-$package.xcresult"
log="${TMPDIR:-/tmp}/homepad-test-$package.log"

cd "$root/Packages/$package" || exit 1

# A package with several products gets a <PackageName>-Package scheme, which is the one that
# holds the tests. A package with one product has only the scheme named after it.
schemes="$(xcodebuild -list -clonedSourcePackagesDirPath "$derived/SourcePackages" 2>/dev/null \
  | sed -e 's/^[[:space:]]*//')"
if print -r -- "$schemes" | grep -qx -- "$package-Package"; then
  scheme="$package-Package"
elif print -r -- "$schemes" | grep -qx -- "$package"; then
  scheme="$package"
else
  echo "no scheme for $package in $PWD"
  exit 1
fi

coverage=YES
[[ -n "${(M)@:#-(only|skip)-testing*}" ]] && coverage=NO

trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1' EXIT
trap 'exit 130' INT TERM

rm -rf "$result"
nice -n 10 xcodebuild test -scheme "$scheme" \
  -destination "platform=iOS Simulator,name=$device" \
  -derivedDataPath "$derived" -jobs 3 \
  -enableCodeCoverage "$coverage" -parallel-testing-enabled NO \
  -resultBundlePath "$result" "$@" > "$log" 2>&1
code=$?

# The lines that start with an arrow under a failure carry its comment and the compared values.
awk '
  /error: |unexpected exit|Test run with [0-9]+ tests? in [0-9]+ suites?|Testing failed|\*\* TEST/ { issue = 0; print; next }
  /recorded an issue/ { issue = 1; print; next }
  /^↳ / && issue { print; next }
  { issue = 0 }
' "$log" | cut -c1-400 | awk '!seen[$0]++' | head -80

# Every other target in the report is a dependency or the test bundle.
target="${package}Core"
[[ -d "Sources/$target" ]] || target="$package"
if [[ "$coverage" == YES && -d "$result" ]]; then
  report="$(xcrun xccov view --report --only-targets "$result" 2>/dev/null)"
  line="$(print -r -- "$report" | awk -v name="$target" '$2 == name')"
  if [[ -n "$line" ]]; then
    print -r -- "$line" | awk '{ print "coverage " $2 ": " $(NF-1) " " $NF }'
    xcrun xccov view --report --files-for-target "$target" "$result" 2>/dev/null \
      | awk '$2 ~ /\.swift$/ && $(NF-1) != "100.00%" { print "  below 100%: " $2 " " $(NF-1) " " $NF }'
  else
    echo "coverage $target: not in the report"
  fi
fi

echo "exit $code (scheme $scheme, full log: $log, result: $result)"
exit $code
