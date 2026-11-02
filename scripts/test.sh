#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
xcrun swiftc -module-cache-path "$PWD/build/ModuleCache" Sources/RuntimePolicy.swift Tests/main.swift -o build/policy-tests
build/policy-tests
