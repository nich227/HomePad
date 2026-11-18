#!/bin/zsh
# Runs a package's unit tests on the macOS host. The packages declare iOS only; HOMEPAD_HOST_TESTS
# makes their manifests add macOS for this run, because this machine has no iOS simulator runtime.
# Usage: Scripts/test-package.sh <PackageName> [extra swift-test args]
set -euo pipefail

root="${0:A:h:h}"
package="${1:?package name}"
shift

cd "$root/Packages/$package"
export HOMEPAD_HOST_TESTS=1
exec nice -n 10 swift test -j 3 --scratch-path "$root/build/spm/$package" --enable-code-coverage "$@"
