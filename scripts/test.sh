#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
xcrun swiftc -module-cache-path "$PWD/build/ModuleCache" Sources/RuntimePolicy.swift Tests/main.swift -o build/policy-tests
build/policy-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/ModuleCache" Sources/MenuReader.swift Tests/MenuReader/main.swift -o build/menu-reader-tests -framework AppKit
build/menu-reader-tests
