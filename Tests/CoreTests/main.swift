// Dependency-free test runner for Sources/dotshot/Core.swift (XCTest is not part of the Command Line Tools).
// Run: ./scripts/test.sh
import Foundation

var failures = 0
var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL \(file):\(line) \(message)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    expect(actual == expected, "\(message) expected \(expected), got \(actual)", file: file, line: line)
}

func url(_ string: String) -> URL { URL(string: string)! }

// MARK: Destination parsing
do {
    let text = """
    # name\tssh-host-or-alias\tremote-folder
    work\tjohn@mac-studio.local\t~/inbound
    nas\tadmin@nas\t/srv/inbound\textra-column
    broken-line-without-tabs
    \t\t
    spaced \t  spark  \t /home/me/inbound \r
    """
    let parsed = DestinationFormat.parse(text)
    expectEqual(parsed.map(\.id), ["work", "nas", "spaced"], "parse keeps valid rows")
    expectEqual(parsed.last?.host, "spark", "parse trims fields")
    expectEqual(parsed.first?.remotePath, "~/inbound")

    let roundTrip = DestinationFormat.parse(DestinationFormat.serialize(parsed))
    expectEqual(roundTrip, parsed, "serialize round-trips")
}

// MARK: Destination validation
do {
    expect(DestinationFormat.isValidHost("john@100.64.0.10"), "tailscale IP host")
    expect(DestinationFormat.isValidHost("studio"), "alias host")
    expect(!DestinationFormat.isValidHost("-oProxyCommand=evil"), "option-looking host rejected")
    expect(!DestinationFormat.isValidHost("john@my mac"), "host with space rejected")
    expect(!DestinationFormat.isValidHost(""), "empty host rejected")

    expect(DestinationFormat.isValidRemotePath("~"), "~ allowed")
    expect(DestinationFormat.isValidRemotePath("~/inbound"), "~/ allowed")
    expect(DestinationFormat.isValidRemotePath("/srv/in bound"), "absolute with space allowed")
    expect(!DestinationFormat.isValidRemotePath("inbound"), "relative rejected")
    expect(!DestinationFormat.isValidRemotePath("~other/inbound"), "~user rejected")
    expect(!DestinationFormat.isValidRemotePath("/a\nb"), "newline rejected")

    expect(DestinationFormat.isValidName("work-mac"), "simple name")
    expect(!DestinationFormat.isValidName("work mac"), "name with space rejected")

    let cleaned = DestinationFormat.cleaned([
        Destination(id: " work ", host: " john@studio ", remotePath: " ~/inbound "),
        Destination(id: "nas", host: "nas", remotePath: "/srv/inbound"),
    ])
    expectEqual(cleaned?.first, Destination(id: "work", host: "john@studio", remotePath: "~/inbound"), "cleaned trims")
    expect(DestinationFormat.cleaned([
        Destination(id: "work", host: "a", remotePath: "/x"),
        Destination(id: "work", host: "b", remotePath: "/y"),
    ]) == nil, "duplicate names rejected")
    expect(DestinationFormat.cleaned([Destination(id: "work", host: "", remotePath: "/x")]) == nil, "one invalid row rejects all")
}

// MARK: URL routing
do {
    expectEqual(parseCaptureURL(url("dotshot://image"), screenCount: 2), .image(dest: nil))
    expectEqual(parseCaptureURL(url("dotshot://shot?dest=work"), screenCount: 2), .image(dest: "work"))
    expectEqual(parseCaptureURL(url("DOTSHOT://Screenshot?dest=nas"), screenCount: 1), .image(dest: "nas"), "scheme/action case-insensitive")
    expectEqual(parseCaptureURL(url("dotshot:///image?dest="), screenCount: 1), .image(dest: nil), "path form, empty dest")
    expectEqual(parseCaptureURL(url("dotshot://video?dest=work"), screenCount: 2), .videoPicker(dest: "work"))
    expectEqual(parseCaptureURL(url("dotshot://video?dest=work&screen=2"), screenCount: 2), .videoDisplay(dest: "work", screen: 2))
    expectEqual(parseCaptureURL(url("dotshot://video?screen=3"), screenCount: 2), .videoPicker(dest: nil), "out-of-range screen falls back to picker")
    expectEqual(parseCaptureURL(url("dotshot://record?screen=REGION"), screenCount: 2), .videoRegion(dest: nil))
    expectEqual(parseCaptureURL(url("dotshot://settings"), screenCount: 1), .setup(step: "destinations"))
    expectEqual(parseCaptureURL(url("dotshot://setup?step=appearance"), screenCount: 1), .setup(step: "appearance"))
    expectEqual(parseCaptureURL(url("dotshot://onboarding"), screenCount: 1), .setup(step: nil))
    expectEqual(parseCaptureURL(url("shotpill://image"), screenCount: 1), .unknown, "legacy scheme is not handled")
    expectEqual(parseCaptureURL(url("dotshot://delete-everything"), screenCount: 1), .unknown)
}

// MARK: Destination resolution
do {
    let available = ["work", "nas"]
    expectEqual(resolveDestination(requested: "nas", saved: "work", available: available), "nas")
    expectEqual(resolveDestination(requested: "missing", saved: "nas", available: available), "nas")
    expectEqual(resolveDestination(requested: nil, saved: "gone", available: available), "work")
    expectEqual(resolveDestination(requested: "work", saved: nil, available: []), nil, "nothing configured")
}

// MARK: Drop grid
do {
    let size = CGSize(width: 320, height: 224)
    expectEqual(DropGrid.tileIndex(at: CGPoint(x: 300, y: 200), in: size, count: 1), 0, "one destination fills the grid")
    expectEqual(DropGrid.tileIndex(at: CGPoint(x: 10, y: 200), in: size, count: 2), 0, "two destinations split left/right")
    expectEqual(DropGrid.tileIndex(at: CGPoint(x: 300, y: 10), in: size, count: 2), 1)
    expectEqual(DropGrid.tileIndex(at: CGPoint(x: 10, y: 200), in: size, count: 3), 2, "third tile bottom-left")
    expectEqual(DropGrid.tileIndex(at: CGPoint(x: 300, y: 200), in: size, count: 3), nil, "empty fourth cell")
    expectEqual(DropGrid.tileIndex(at: CGPoint(x: 300, y: 200), in: size, count: 9), 3, "capped at four tiles")
    expectEqual(DropGrid.tileIndex(at: CGPoint(x: -5, y: 999), in: size, count: 4), 2, "out-of-bounds points clamp")
    expectEqual(DropGrid.tileIndex(at: CGPoint(x: 0, y: 0), in: size, count: 0), nil)
    expectEqual(DropGrid.rows(for: 3), 2)
}

// MARK: Shell quoting
do {
    expectEqual(shellSingleQuote("it's"), "'it'\\''s'")
    expectEqual(remotePathExpression("~"), "\"$HOME\"")
    expectEqual(remotePathExpression("~/in box"), "\"$HOME\"/'in box'")
    expectEqual(remotePathExpression("/srv/$(reboot)"), "'/srv/$(reboot)'", "command substitution stays literal")
}

// MARK: Paths
do {
    let paths = Paths(home: "/Users/test", environment: [:])
    expectEqual(paths.shots, "/Users/test/Shots")
    expectEqual(paths.destinationsFile, "/Users/test/Library/Application Support/dotshot/destinations.tsv")
    expectEqual(paths.legacyConfigDir, "/Users/test/Library/Application Support/Shot Pill")
    let overridden = Paths(home: "/Users/test", environment: ["DOTSHOT_CONFIG_DIR": "/tmp/cfg", "DOTSHOT_SHOTS_DIR": "/tmp/shots"])
    expectEqual(overridden.destinationsFile, "/tmp/cfg/destinations.tsv")
    expectEqual(overridden.shots, "/tmp/shots")
    expect(overridden.isIsolated && !paths.isIsolated, "config override marks an isolated instance")
}

// MARK: Shot Pill migration
do {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent("dotshot-tests-\(UUID().uuidString)").path
    defer { try? fm.removeItem(atPath: home) }
    let paths = Paths(home: home, environment: [:])
    try! fm.createDirectory(atPath: paths.legacyConfigDir, withIntermediateDirectories: true)
    let legacyRows = "# header\nwork\twork\t/Users/me/inbound\n"
    try! legacyRows.write(toFile: paths.legacyConfigDir + "/destinations.tsv", atomically: true, encoding: .utf8)

    let newSuite = "dotshot.tests.new.\(UUID().uuidString)"
    let oldSuite = "dotshot.tests.old.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: newSuite)!
    let legacy = UserDefaults(suiteName: oldSuite)!
    defer {
        defaults.removePersistentDomain(forName: newSuite)
        legacy.removePersistentDomain(forName: oldSuite)
    }
    legacy.set(3, forKey: "shotpill.accentIndex")
    legacy.set("work", forKey: "shotpill.dest")
    legacy.set(true, forKey: "shotpill.onboardingComplete")
    defaults.set("topLeft", forKey: "dotshot.position")
    legacy.set("bottomLeft", forKey: "shotpill.position")

    let result = LegacyMigration.run(paths: paths, defaults: defaults, legacyDefaults: legacy)
    expect(result.copiedDestinations, "destinations copied")
    expectEqual((try? String(contentsOfFile: paths.destinationsFile, encoding: .utf8)), legacyRows)
    expectEqual(Set(result.copiedDefaults), ["accentIndex", "dest", "onboardingComplete"])
    expectEqual(defaults.integer(forKey: "dotshot.accentIndex"), 3)
    expectEqual(defaults.string(forKey: "dotshot.position"), "topLeft", "existing dotshot value wins")

    let second = LegacyMigration.run(paths: paths, defaults: defaults, legacyDefaults: legacy)
    expectEqual(second, LegacyMigration.Result(), "migration runs once")

    // A fresh install without Shot Pill does nothing.
    let emptyHome = home + "/fresh"
    let freshSuite = "dotshot.tests.fresh.\(UUID().uuidString)"
    let fresh = UserDefaults(suiteName: freshSuite)!
    defer { fresh.removePersistentDomain(forName: freshSuite) }
    let none = LegacyMigration.run(paths: Paths(home: emptyHome, environment: [:]), defaults: fresh, legacyDefaults: nil)
    expectEqual(none, LegacyMigration.Result())
    expect(!fm.fileExists(atPath: Paths(home: emptyHome, environment: [:]).destinationsFile), "no config created")
}

print("\(checks - failures)/\(checks) core checks passed")
exit(failures == 0 ? 0 : 1)
