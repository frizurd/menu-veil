#!/bin/zsh
# Exercise the real AppDelegate transition with a visible AppKit panel.
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/SwitchHarness
python3 - <<'PY'
from pathlib import Path
source = Path('Sources/main.swift').read_text().rsplit('\nlet app = NSApplication.shared', 1)[0]
source += '''
extension AppDelegate {
    func checkSwitchContinuity() -> Bool {
        enabled = true; trusted = true; awake = true; pid = -1
        guard let screen = NSScreen.screens.first else { print("FAIL: no display"); return false }
        let frame = CGRect(x: screen.frame.minX, y: 0, width: 400, height: 32)
        measurement = MenuMeasurement(pid: -1, frame: frame, tracking: false, count: 7)
        measuredAt = Date()
        applyGeometry(measurement!)
        refreshVisibility()
        guard let original = covers.first else { print("FAIL: no initial cover"); return false }
        original.alphaValue = 1
        let before = original.isVisible && original.targetAlpha == 1
        guard let nextApp = NSWorkspace.shared.frontmostApplication else { return false }
        widthCache[cacheKey(for: nextApp.processIdentifier, screen: screen)] = 550
        frontChanged()
        let cached = original.frame.width == 550
        let during = covers.first === original && original.isVisible && original.targetAlpha == 1
        print(before ? "PASS initial cover visible" : "FAIL initial cover not visible")
        print(during ? "PASS app switch retains the visible panel" : "FAIL app switch destroys or hides the cover")
        print(cached ? "PASS cached next-app width applied without hiding" : "FAIL next-app width not applied")
        switchingUntil = nil
        switchExpiryTask?.cancel()
        measuredAt = Date()
        measurement = MenuMeasurement(pid: pid, frame: CGRect(x: screen.frame.minX, y: 0, width: 520, height: 32), tracking: false, count: 8)
        applyGeometry(measurement!); refreshVisibility()
        let resized = covers.first === original && original.targetAlpha == 1 && original.frame.width == 526
        print(resized ? "PASS measured bounds replace cache without a fade" : "FAIL measured bounds recreate or fade the cover")
        covers.forEach { $0.orderOut(nil); $0.close() }
        return before && during && cached && resized
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = AppDelegate()
let passed = controller.checkSwitchContinuity()
exit(passed ? 0 : 1)
'''
Path('build/SwitchHarness/main.swift').write_text(source)
PY
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/ModuleCache" Sources/CoverPanel.swift Sources/MenuReader.swift Sources/RuntimePolicy.swift build/SwitchHarness/main.swift -o build/switch-harness -framework AppKit
build/switch-harness --allow-development
