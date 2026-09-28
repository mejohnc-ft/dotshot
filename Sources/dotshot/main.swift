// main.swift — dotshot entry point.
import AppKit

if !PATHS.isIsolated {
    let migration = LegacyMigration.run(
        paths: PATHS,
        defaults: .standard,
        legacyDefaults: UserDefaults(suiteName: Brand.legacyBundleID)
    )
    if migration.copiedDestinations || !migration.copiedDefaults.isEmpty {
        NSLog("dotshot: migrated Shot Pill settings (destinations: \(migration.copiedDestinations), defaults: \(migration.copiedDefaults))")
    }

    // Shot Pill is this app's previous name; both would fight over the same global shortcuts.
    for legacy in NSRunningApplication.runningApplications(withBundleIdentifier: Brand.legacyBundleID) {
        NSLog("dotshot: quitting the previous Shot Pill app")
        legacy.terminate()
    }
}

// Registered after migration so defaults never mask a legacy value.
UserDefaults.standard.register(defaults: [
    "dotshot.accentIndex": 0,
    "dotshot.position": "bottomRight",
    "dotshot.inset": 24.0
])

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
