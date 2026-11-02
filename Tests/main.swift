import Foundation
let now = Date()
func check(_ condition: @autoclosure () -> Bool, _ name: String) { precondition(condition(), name); print("PASS \(name)") }
func cover(_ installed: Bool = true, _ trusted: Bool = true, _ enabled: Bool = true, _ awake: Bool = true, _ age: Double? = 0) -> Bool {
    RuntimePolicy.mayCover(installed: installed, trusted: trusted, enabled: enabled, awake: awake, measuredAt: age.map { now.addingTimeInterval(-$0) }, now: now)
}
check(cover(), "valid measurement allows cover")
check(!cover(false), "uninstalled app cannot obscure menus")
check(!cover(true, false), "denied or revoked permission exposes menus")
check(!cover(true, true, false), "pause exposes menus")
check(!cover(true, true, true, false), "sleep exposes menus")
check(!cover(true, true, true, true, nil), "missing geometry exposes menus")
check(!cover(true, true, true, true, 6), "stale geometry exposes menus")
check(!cover(true, true, true, true, -1), "invalid future timestamp exposes menus")
let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
check(RuntimePolicy.belongsToDisplay(menu: CGRect(x: 10,y: 0,width: 376,height: 32), display: screen), "actual menu belongs to primary display")
check(!RuntimePolicy.belongsToDisplay(menu: CGRect(x: 1800,y: 0,width: 376,height: 32), display: screen), "do not reuse width on another display")
check(!RuntimePolicy.belongsToDisplay(menu: CGRect(x: 0,y: 100,width: 376,height: 32), display: screen), "reject dropdown geometry")
check(RuntimePolicy.measurementInterval(revealed: false) > RuntimePolicy.measurementInterval(revealed: true), "idle measurement rate is lower")
check(RuntimePolicy.acceptsResult(generation: 1, requestedGeneration: 1, pid: 42, requestedPID: 42, trusted: true, awake: true, startedAt: now, now: now), "accept current result")
check(!RuntimePolicy.acceptsResult(generation: 2, requestedGeneration: 1, pid: 42, requestedPID: 42, trusted: true, awake: true, startedAt: now, now: now), "discard result after state change")
check(!RuntimePolicy.acceptsResult(generation: 1, requestedGeneration: 1, pid: 43, requestedPID: 42, trusted: true, awake: true, startedAt: now, now: now), "discard previous app result")
check(!RuntimePolicy.acceptsResult(generation: 1, requestedGeneration: 1, pid: 42, requestedPID: 42, trusted: true, awake: true, startedAt: now.addingTimeInterval(-2), now: now), "discard slow or hung app result")
