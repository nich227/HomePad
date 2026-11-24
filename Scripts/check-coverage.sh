#!/bin/zsh
# Fails when a package's logic target is below 100% line coverage.
# Usage: Scripts/check-coverage.sh <PackageName> <file holding the output of test-package.sh>
# The logic target is <PackageName>Core, or the package's only target when its name ends in Core.
# A package with no logic target has no floor.
set -uo pipefail

root="${0:A:h:h}"
package="${1:?package name}"
output="${2:?output of Scripts/test-package.sh}"

target="${package}Core"
[[ -d "$root/Packages/$package/Sources/$target" ]] || target="$package"
if [[ "$target" != *Core ]]; then
  echo "$target has no coverage floor"
  exit 0
fi
if grep -q "^coverage $target: 100.00% " "$output"; then
  grep "^coverage $target: " "$output"
  exit 0
fi
echo "::error::$target is below 100% line coverage"
grep -E "^coverage |below 100%" "$output"
exit 1
