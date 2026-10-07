#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
  src/Options.m tests/options_tests.m -o build/options-tests
build/options-tests
binary="build/virtual-display-free-macos.app/Contents/MacOS/virtual-display-free-macos"
"$binary" --help >/dev/null
"$binary" --version
"$binary" --list-displays >/dev/null
printf 'Testes sem alteração de telas passaram.\n'
