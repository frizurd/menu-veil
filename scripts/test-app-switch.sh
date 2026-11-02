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
        enabled = true; trusted = true; awake = true; pid = -1; hoverEnabled = false
        reading = true // Hold the AX query to exercise the entire pending handoff.
        guard let screen = NSScreen.screens.first else { print("FAIL: no display"); return false }
        let frame = CGRect(x: screen.frame.minX, y: 0, width: 900, height: 32)
        measurement = MenuMeasurement(pid: -1, frame: frame, tracking: false, count: 7)
        measuredAt = Date()
        applyGeometry(measurement!)
        refreshVisibility()
        guard let original = covers.first else { print("FAIL: no initial cover"); return false }
        original.alphaValue = 1
        let before = original.isVisible && original.targetAlpha == 1
        guard NSWorkspace.shared.frontmostApplication != nil else { return false }
        frontChanged()
        // The next app's 850-point menu must stay covered while a slow read
        // for another app is in flight, even if an early sample is shorter.
        let cached = original.frame.width >= 856
        let during = covers.first === original && original.isVisible && original.targetAlpha == 1
        print(before ? "PASS initial cover visible" : "FAIL initial cover not visible")
        print(during ? "PASS app switch retains the visible panel" : "FAIL app switch destroys or hides the cover")
        print(cached ? "PASS retained width covers longer menus during handoff" : "FAIL handoff exposes the right end of the next app menu")
        switchingUntil = nil
        switchExpiryTask?.cancel()
        measuredAt = Date()
        measurement = MenuMeasurement(pid: pid, frame: CGRect(x: screen.frame.minX, y: 0, width: 520, height: 32), tracking: false, count: 8)
        receiveMeasurement(measurement, requestedPID: pid, token: generation, startedAt: Date())
        let followup = queryTask != nil
        let resized = covers.first === original && original.targetAlpha == 1 && original.frame.width >= 906
        print(resized ? "PASS short early measurement cannot shrink the cover" : "FAIL short early measurement exposes long menus")
        print(followup ? "PASS first successful read schedules settling measurements" : "FAIL first success ends measurement too early")
        receiveMeasurement(nil, requestedPID: pid, token: generation, startedAt: Date())
        let incomplete = covers.first === original && original.targetAlpha == 1 && queryTask != nil
        print(incomplete ? "PASS incomplete settling read retains cover and retries" : "FAIL incomplete settling read tears down cover")
        let oldPID = pid, oldGeneration = generation
        beginHandoff(to: -99)
        receiveMeasurement(nil, requestedPID: oldPID, token: oldGeneration, startedAt: Date())
        let stale = covers.first === original && pid == -99 && original.targetAlpha == 1
        print(stale ? "PASS delayed previous-app failure cannot tear down new cover" : "FAIL stale failure invalidates current cover")
        var rapid = true
        var widest: CGFloat = 906
        for index in 0..<100 {
            beginHandoff(to: -100 - Int32(index))
            // An early short layout arrives before the final long layout.
            measuredAt = Date()
            applyGeometry(MenuMeasurement(pid: pid, frame: CGRect(x: screen.frame.minX, y: 0, width: 300, height: 32), tracking: false, count: 5))
            rapid = rapid && covers.first === original && original.frame.width >= widest && original.targetAlpha == 1
            let width = CGFloat(700 + index * 3)
            applyGeometry(MenuMeasurement(pid: pid, frame: CGRect(x: screen.frame.minX, y: 0, width: width, height: 32), tracking: false, count: 10))
            widest = max(widest, width + 6)
            refreshVisibility(animate: false)
            rapid = rapid && original.frame.width >= widest && original.alphaValue == 1
        }
        print(rapid ? "PASS 100 rapid handoffs preserve complete coverage and opacity" : "FAIL rapid handoffs expose menu text")
        settlingUntil = .distantPast
        applyGeometry(MenuMeasurement(pid: pid, frame: CGRect(x: screen.frame.minX, y: 0, width: 300, height: 32), tracking: false, count: 5))
        let settled = original.frame.width == 306
        print(settled ? "PASS settled menu releases guard space for status icons" : "FAIL guard permanently occupies status icon space")
        beginHandoff(to: -500)
        let restored = original.frame.width >= widest && original.alphaValue == 1
        print(restored ? "PASS next switch restores the wider guard immediately" : "FAIL next switch starts with short coverage")
        queryTask?.cancel(); queryTask = nil
        scheduleQuery()
        let pending = queryTask
        for _ in 0..<100 { scheduleQuery() }
        let coalesced = pending === queryTask
        print(coalesced ? "PASS notification burst cannot postpone the pending read" : "FAIL notification burst starves measurement")
        // Expiry must still remove the guard if no usable new geometry arrives.
        let expiry = switchExpiryTask
        expiry?.perform()
        let expired = covers.isEmpty && measuredAt == nil
        print(expired ? "PASS failed handoff removes its cover" : "FAIL failed handoff retains stale cover")
        return before && during && cached && resized && followup && incomplete && stale && rapid && settled && restored && coalesced && expired
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
