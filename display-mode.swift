// display-mode.swift
//
// Applies (or checks) the exact display mode for the ASUS VG32VQ1B.
// Compiled by install.sh into build/display-mode.
//
// Usage:
//   display-mode --width 2560 --height 1440 --refresh 144 [--vendor 1715] [--model 13024]
//   display-mode --width 2560 --height 1440 --refresh 144 --check
//   display-mode --status
//
// Exit codes:
//   0  mode applied, already correct, or status printed
//   2  no matching external display found
//   3  requested mode is not offered by the display
//   4  the system refused to apply the mode
//   1  bad arguments

import CoreGraphics
import Foundation

struct Options {
    var width = 2560
    var height = 1440
    var refresh = 144.0
    var vendor: Int?
    var model: Int?
    var checkOnly = false
    var status = false
}

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func parseOptions() -> Options {
    var options = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var index = 0

    func value(_ name: String) -> String {
        index += 1
        guard index < args.count else { fail("missing value for \(name)", 1) }
        return args[index]
    }

    while index < args.count {
        switch args[index] {
        case "--width":   options.width = Int(value("--width")) ?? 0
        case "--height":  options.height = Int(value("--height")) ?? 0
        case "--refresh": options.refresh = Double(value("--refresh")) ?? 0
        case "--vendor":  options.vendor = Int(value("--vendor"))
        case "--model":   options.model = Int(value("--model"))
        case "--check":   options.checkOnly = true
        case "--status":  options.status = true
        case "-h", "--help":
            print("usage: display-mode --width W --height H --refresh R [--vendor V] [--model M] [--check] [--status]")
            exit(0)
        default:
            fail("unknown argument: \(args[index])", 1)
        }
        index += 1
    }

    if !options.status && (options.width <= 0 || options.height <= 0 || options.refresh <= 0) {
        fail("width, height and refresh must be positive", 1)
    }
    return options
}

func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    guard count > 0 else { return [] }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &displays, &count)
    return Array(displays.prefix(Int(count)))
}

func displayLabel(_ id: CGDirectDisplayID) -> String {
    "id=\(id) vendor=\(CGDisplayVendorNumber(id)) model=\(CGDisplayModelNumber(id))"
}

func modeString(_ mode: CGDisplayMode) -> String {
    String(format: "%dx%d@%.0fHz", mode.width, mode.height, mode.refreshRate)
}

let options = parseOptions()
let displays = onlineDisplays()

if options.status {
    if displays.isEmpty {
        print("no online displays")
        exit(2)
    }
    for id in displays {
        let kind = CGDisplayIsBuiltin(id) != 0 ? "built-in" : "external"
        let current = CGDisplayCopyDisplayMode(id).map(modeString) ?? "unknown"
        print("\(kind) \(displayLabel(id)) current=\(current)")
    }
    exit(0)
}

// Pick the external display. Vendor/model come straight from EDID and are
// stable across reboots, unlike the macOS display UUID.
let candidates = displays.filter { id in
    guard CGDisplayIsBuiltin(id) == 0 else { return false }
    if let vendor = options.vendor, Int(CGDisplayVendorNumber(id)) != vendor { return false }
    if let model = options.model, Int(CGDisplayModelNumber(id)) != model { return false }
    return true
}

guard let display = candidates.first else {
    fail("no matching external display online", 2)
}

let lookupOptions = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
let allModes = (CGDisplayCopyAllDisplayModes(display, lookupOptions) as? [CGDisplayMode]) ?? []

// width/height are points, so exact native 1:1 modes are selected, not
// HiDPI variants (which have width=1280, pixelWidth=2560).
let matching = allModes.filter {
    $0.width == options.width && $0.height == options.height && $0.isUsableForDesktopGUI()
}

guard !matching.isEmpty else {
    let offered = allModes
        .filter { $0.width == options.width && $0.height == options.height }
        .map { String(format: "%.0f", $0.refreshRate) }
        .sorted()
    let list = offered.isEmpty ? "none" : offered.joined(separator: ", ")
    fail("\(options.width)x\(options.height) is not offered by \(displayLabel(display)) (refresh rates: \(list))", 3)
}

// Prefer the requested refresh; otherwise the closest available rate.
let target = matching.min { abs($0.refreshRate - options.refresh) < abs($1.refreshRate - options.refresh) }!

if let current = CGDisplayCopyDisplayMode(display),
   current.width == target.width,
   current.height == target.height,
   abs(current.refreshRate - target.refreshRate) < 0.01,
   CGDisplayIsInMirrorSet(display) == 0 {
    print("already \(modeString(target)) (\(displayLabel(display)))")
    exit(0)
}

if options.checkOnly {
    let current = CGDisplayCopyDisplayMode(display).map(modeString) ?? "unknown"
    fail("mode is \(current), want \(modeString(target))", 4)
}

var configuration: CGDisplayConfigRef?
let begin = CGBeginDisplayConfiguration(&configuration)
guard begin == .success, let configuration else {
    fail("could not begin a display configuration (error \(begin.rawValue))", 4)
}

// A stale mirrored configuration is what brings the fake 4K desktop back on
// some boots, so explicitly leave any mirror set.
CGConfigureDisplayMirrorOfDisplay(configuration, display, kCGNullDirectDisplay)
let configure = CGConfigureDisplayWithDisplayMode(configuration, display, target, nil)
guard configure == .success else {
    CGCancelDisplayConfiguration(configuration)
    fail("could not configure display mode (error \(configure.rawValue))", 4)
}

let complete = CGCompleteDisplayConfiguration(configuration, .forSession)
guard complete == .success else {
    fail("could not apply display configuration (error \(complete.rawValue))", 4)
}

if let applied = CGDisplayCopyDisplayMode(display) {
    print("applied \(modeString(applied)) (\(displayLabel(display)))")
    exit(0)
}
print("applied \(modeString(target)) (\(displayLabel(display)))")
