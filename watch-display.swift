// watch-display.swift
//
// Long-running login agent. It runs apply-settings.sh:
//   - once at startup (login / boot)
//   - after system or screen wake
//   - when the set of connected displays changes (cable reconnect)
//
// It deliberately ignores mode-only reconfiguration events, so manually
// choosing a different refresh rate in System Settings is not fought.
// Compiled by install.sh into build/watch-display.

import AppKit
import CoreGraphics
import Foundation

let applyScript: String = {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments[1]
    }
    let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    return binary.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("apply-settings.sh").path
}()

let logFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

func log(_ message: String) {
    print("\(logFormatter.string(from: Date())) agent: \(message)")
    fflush(stdout)
}

let applyQueue = DispatchQueue(label: "vg32vq1b.apply", qos: .utility)
let stateLock = NSLock()
var pending: DispatchWorkItem?
var modeWatchDeadline = Date.distantPast
var retryDeadline = Date.distantPast
var retryAttempt = 0
var generation = 0

// apply-settings.sh exits 2 when the display is not enumerable yet (login,
// wake, cable reconnect, monitor still powered off). Retry with a fixed
// backoff until the window has passed, then stop: an all-day poll of a
// switched-off monitor is pointless and fights nothing.
let retryInterval: TimeInterval = 15
let retryWindow: TimeInterval = 300
let maxRetryAttempts = 20

// The CG display callback is not reliable in a background LaunchAgent: in two
// days of log it never fired once, even across unplug/replug. So also poll the
// set of connected external displays. This only triggers on a *set* change
// (plug / unplug / new display id), never on a mode change, so a refresh rate
// chosen by hand is still not fought.
let watchdogInterval: TimeInterval = 60
var lastFingerprint: String?

func externalFingerprint() -> String {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    guard count > 0 else { return "" }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return ids.prefix(Int(count))
        .filter { CGDisplayIsBuiltin($0) == 0 }
        .map { "\(CGDisplayVendorNumber($0)):\(CGDisplayModelNumber($0)):\($0)" }
        .joined(separator: ",")
}

// After startup/wake/reconnect macOS sometimes settles on the wrong mode a
// few seconds late. Watch mode changes for a short window so those get
// corrected, but ignore later ones so manual changes are not fought.
func armModeWatch() {
    stateLock.lock()
    modeWatchDeadline = Date().addingTimeInterval(60)
    stateLock.unlock()
}

func modeWatchArmed() -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return Date() < modeWatchDeadline
}

func performApply(reason: String, attempt: Int, gen: Int) {
    let label = attempt > 0 ? "\(reason), retry \(attempt)/\(maxRetryAttempts)" : reason
    log("applying (\(label))")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [applyScript]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        log("could not run apply-settings.sh: \(error)")
        return
    }

    let status = process.terminationStatus
    log("apply finished with status \(status)")

    if status == 0 {
        stateLock.lock()
        lastFingerprint = externalFingerprint()
        stateLock.unlock()
    }

    // Anything other than "display not available yet" is final: a missing
    // mode or a refused configuration will not fix itself by asking again.
    guard status == 2 else { return }

    stateLock.lock()
    let canRetry = gen == generation
        && Date() < retryDeadline
        && retryAttempt < maxRetryAttempts
    if canRetry { retryAttempt += 1 }
    stateLock.unlock()

    if canRetry {
        log("display not available yet; retrying in \(Int(retryInterval))s")
        scheduleApply(reason: "display missing", delay: retryInterval, fresh: false)
    } else {
        log("display still not available; waiting for the next login/wake/reconnect")
    }
}

func scheduleApply(reason: String, delay: TimeInterval = 3.0, fresh: Bool = true) {
    stateLock.lock()
    pending?.cancel()
    if fresh {
        generation += 1
        retryAttempt = 0
        retryDeadline = Date().addingTimeInterval(retryWindow)
    }
    let attempt = retryAttempt
    let gen = generation
    let item = DispatchWorkItem { performApply(reason: reason, attempt: attempt, gen: gen) }
    pending = item
    stateLock.unlock()
    applyQueue.asyncAfter(deadline: .now() + delay, execute: item)
}

func checkDisplaySet() {
    let fingerprint = externalFingerprint()

    stateLock.lock()
    let previous = lastFingerprint
    lastFingerprint = fingerprint
    stateLock.unlock()

    // The first tick only primes the baseline; the startup apply already ran.
    guard let previous else { return }
    guard fingerprint != previous else { return }

    if fingerprint.isEmpty {
        // Unplugged. Stop any pending retries instead of polling a monitor
        // that is not connected; the next set change brings us back.
        log("external display disconnected; waiting for reconnect")
        stateLock.lock()
        pending?.cancel()
        retryAttempt = 0
        retryDeadline = Date.distantPast
        stateLock.unlock()
        return
    }

    armModeWatch()
    scheduleApply(reason: "display set changed", delay: 1.0)
}

let watchdogQueue = DispatchQueue(label: "vg32vq1b.watchdog", qos: .utility)
let watchdog = DispatchSource.makeTimerSource(queue: watchdogQueue)
watchdog.schedule(deadline: .now() + watchdogInterval, repeating: watchdogInterval)
watchdog.setEventHandler { checkDisplaySet() }
watchdog.resume()

// Display connect/disconnect, plus mode changes during the short settling
// window after startup/wake. Mode changes made by hand later are ignored.
let displayCallback: CGDisplayReconfigurationCallBack = { _, flags, _ in
    if flags.contains(.addFlag) || flags.contains(.removeFlag) {
        armModeWatch()
        scheduleApply(reason: "display connected or removed")
    } else if flags.contains(.setModeFlag), modeWatchArmed() {
        scheduleApply(reason: "mode settled late")
    }
}
CGDisplayRegisterReconfigurationCallback(displayCallback, nil)

let workspaceCenter = NSWorkspace.shared.notificationCenter
workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
    armModeWatch()
    scheduleApply(reason: "system wake", delay: 4.0)
}
workspaceCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
    armModeWatch()
    scheduleApply(reason: "screen wake", delay: 4.0)
}

log("started; script=\(applyScript)")
armModeWatch()
scheduleApply(reason: "startup", delay: 1.0)
RunLoop.main.run()
