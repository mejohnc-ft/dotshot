// Core.swift — UI-free logic shared by the app and the test runner.
// Paths, destination parsing/validation, URL routing, and migration from Shot Pill.
import Foundation

enum Brand {
    static let name = "dotshot"
    static let bundleID = "com.mejohnc.dotshot"
    static let urlScheme = "dotshot"
    static let legacyBundleID = "com.johnc.shotpill"
    static let legacyConfigFolder = "Shot Pill"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// Environment overrides (DOTSHOT_CONFIG_DIR, DOTSHOT_SHOTS_DIR, demo switches) are honored only by
/// development builds. The released app ignores them, so another process can't relaunch dotshot with
/// `open --env` to redirect captures to its own config or folder.
func developmentOverridesAllowed(bundleID: String?) -> Bool {
    bundleID != Brand.bundleID
}

/// Filesystem locations. Environment overrides exist for tests and documentation captures.
struct Paths {
    let home: String
    let environment: [String: String]

    init(home: String = NSHomeDirectory(), environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.home = home
        self.environment = environment
    }

    var shots: String {
        environment["DOTSHOT_SHOTS_DIR"] ?? (home as NSString).appendingPathComponent("Shots")
    }
    var configDir: String {
        environment["DOTSHOT_CONFIG_DIR"]
            ?? (home as NSString).appendingPathComponent("Library/Application Support/\(Brand.name)")
    }
    /// Tests and documentation captures point dotshot at a private config folder; such instances
    /// leave Shot Pill settings and running apps alone.
    var isIsolated: Bool { environment["DOTSHOT_CONFIG_DIR"] != nil }
    var destinationsFile: String { (configDir as NSString).appendingPathComponent("destinations.tsv") }
    var legacyConfigDir: String {
        (home as NSString).appendingPathComponent("Library/Application Support/\(Brand.legacyConfigFolder)")
    }
}

struct Destination: Identifiable, Equatable {
    var id: String
    var host: String
    var remotePath: String
}

enum DestinationFormat {
    static let header = "# name\tssh-host-or-alias\tremote-folder\n"

    /// Parses destinations.tsv, skipping comments and rows the capture script would reject
    /// (CRLF endings and stray spaces are tolerated), so the app never offers a destination that can't work.
    static func parse(_ text: String) -> [Destination] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine)
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 3 else { return nil }
            let id = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let host = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let path = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidName(id), isValidHost(host), isValidRemotePath(path) else { return nil }
            return Destination(id: id, host: host, remotePath: path)
        }
    }

    static func serialize(_ destinations: [Destination]) -> String {
        header + destinations.map { "\($0.id)\t\($0.host)\t\($0.remotePath)" }.joined(separator: "\n") + "\n"
    }

    /// `user@host`, a hostname or IP, or an ~/.ssh/config alias. No option-looking values, and no `:` or `/`,
    /// which scp would read as a path separator.
    static func isValidHost(_ host: String) -> Bool {
        !host.hasPrefix("-") && host.range(of: #"^[A-Za-z0-9._%+@-]+$"#, options: .regularExpression) != nil
    }

    /// An absolute folder or one under `~/`. The home folder itself and `/` are refused: dotshot writes
    /// files there by name, and a folder of its own keeps captures away from dotfiles.
    static func isValidRemotePath(_ path: String) -> Bool {
        guard path.rangeOfCharacter(from: .controlCharacters) == nil,
              path.hasPrefix("~/") || path.hasPrefix("/") else { return false }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard trimmed != "~", !trimmed.isEmpty else { return false }
        return !path.components(separatedBy: "/").contains("..")
    }

    static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9._-]{1,32}$"#, options: .regularExpression) != nil
    }

    /// Trims every field and returns nil when any destination is invalid or names repeat.
    static func cleaned(_ destinations: [Destination]) -> [Destination]? {
        let cleaned = destinations.map { destination in
            Destination(
                id: destination.id.trimmingCharacters(in: .whitespacesAndNewlines),
                host: destination.host.trimmingCharacters(in: .whitespacesAndNewlines),
                remotePath: destination.remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard cleaned.allSatisfy({ isValidName($0.id) && isValidHost($0.host) && isValidRemotePath($0.remotePath) }),
              Set(cleaned.map(\.id)).count == cleaned.count else { return nil }
        return cleaned
    }
}

enum CaptureAction: Equatable {
    case image(dest: String?)
    case videoPicker(dest: String?)
    case videoDisplay(dest: String?, screen: Int)
    case videoRegion(dest: String?)
    case setup(step: String?)
    case unknown
}

/// Parses dotshot:// automation URLs. Screen numbers are validated against `screenCount`.
func parseCaptureURL(_ url: URL, screenCount: Int) -> CaptureAction {
    guard url.scheme?.lowercased() == Brand.urlScheme else { return .unknown }
    let action = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func query(_ name: String) -> String? {
        queryItems.first(where: { $0.name == name })?.value.flatMap { $0.isEmpty ? nil : $0 }
    }
    let dest = query("dest")

    switch action {
    case "shot", "image", "screenshot":
        return .image(dest: dest)
    case "vid", "video", "record":
        let screen = query("screen")
        if let screen, let number = Int(screen), (1...max(screenCount, 1)).contains(number) {
            return .videoDisplay(dest: dest, screen: number)
        }
        if screen?.lowercased() == "region" { return .videoRegion(dest: dest) }
        return .videoPicker(dest: dest)
    case "settings":
        return .setup(step: query("step") ?? "destinations")
    case "setup", "onboarding":
        return .setup(step: query("step"))
    default:
        return .unknown
    }
}

/// Chooses a configured destination: the requested one, else the saved one, else the first.
/// A requested destination that isn't configured resolves to nil rather than silently sending elsewhere.
func resolveDestination(requested: String?, saved: String?, available: [String]) -> String? {
    if let requested { return available.contains(requested) ? requested : nil }
    if let saved, available.contains(saved) { return saved }
    return available.first
}

/// Drop targets: up to six destinations, one tile for a single destination, two columns for up to four,
/// three columns for five or six.
enum DropGrid {
    static let maxTiles = 6

    static func columns(for count: Int) -> Int { count <= 1 ? 1 : count <= 4 ? 2 : 3 }
    static func rows(for count: Int) -> Int {
        let tiles = min(max(count, 1), maxTiles)
        return (tiles + columns(for: tiles) - 1) / columns(for: tiles)
    }

    /// Index of the tile under `point` (origin top-left) in a grid of `size`, or nil for an empty cell.
    static func tileIndex(at point: CGPoint, in size: CGSize, count: Int) -> Int? {
        let tiles = min(count, maxTiles)
        guard tiles > 0, size.width > 0, size.height > 0 else { return nil }
        let columns = columns(for: tiles), rows = rows(for: tiles)
        let column = min(max(Int(point.x / (size.width / CGFloat(columns))), 0), columns - 1)
        let row = min(max(Int(point.y / (size.height / CGFloat(rows))), 0), rows - 1)
        let index = row * columns + column
        return index < tiles ? index : nil
    }
}

/// The capture script's entire environment. dotshot holds Screen Recording permission and its children
/// inherit it, so nothing from dotshot's own environment (BASH_ENV, PATH, DOTSHOT_* overrides) is passed on.
func scriptEnvironment(paths: Paths, inherited: [String: String] = ProcessInfo.processInfo.environment,
                       namer: String? = UserDefaults.standard.string(forKey: "dotshot.namer")) -> [String: String] {
    var environment = [
        "HOME": paths.home,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "en_US.UTF-8",
        "DOTSHOT_NOTIFY_STDOUT": "1",   // progress comes back on stdout, so notifications come from dotshot
        "DOTSHOT_CONFIG": paths.destinationsFile,
        "DOTSHOT_SHOTS_DIR": paths.shots,
    ]
    for key in ["USER", "LOGNAME", "TMPDIR", "SSH_AUTH_SOCK"] {
        if let value = inherited[key] { environment[key] = value }
    }
    if let namer, ["claude", "codex"].contains(namer) { environment["DOTSHOT_NAMER"] = namer }
    return environment
}

func shellSingleQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// A shell expression for a remote folder that expands `~` on the destination but quotes everything else.
func remotePathExpression(_ path: String) -> String {
    if path == "~" { return "\"$HOME\"" }
    if path.hasPrefix("~/") { return "\"$HOME\"/" + shellSingleQuote(String(path.dropFirst(2))) }
    return shellSingleQuote(path)
}

/// One-time migration of settings from the app's previous name, Shot Pill.
enum LegacyMigration {
    static let doneKey = "dotshot.migratedFromShotPill"
    static let defaultsKeys = ["accentIndex", "dest", "displayName", "inset", "position",
                               "recordingSource", "onboardingComplete"]

    struct Result: Equatable {
        var copiedDestinations = false
        var copiedDefaults: [String] = []
    }

    @discardableResult
    static func run(paths: Paths, defaults: UserDefaults, legacyDefaults: UserDefaults?,
                    fileManager: FileManager = .default) -> Result {
        var result = Result()
        guard !defaults.bool(forKey: doneKey) else { return result }

        let legacyFile = (paths.legacyConfigDir as NSString).appendingPathComponent("destinations.tsv")
        if !fileManager.fileExists(atPath: paths.destinationsFile), fileManager.fileExists(atPath: legacyFile) {
            do {
                try fileManager.createDirectory(atPath: paths.configDir, withIntermediateDirectories: true)
                try fileManager.copyItem(atPath: legacyFile, toPath: paths.destinationsFile)
                result.copiedDestinations = true
            } catch {
                NSLog("dotshot: could not migrate Shot Pill destinations: \(error)")
            }
        }

        if let legacyDefaults {
            for key in defaultsKeys {
                guard defaults.object(forKey: "dotshot.\(key)") == nil,
                      let value = legacyDefaults.object(forKey: "shotpill.\(key)") else { continue }
                defaults.set(value, forKey: "dotshot.\(key)")
                result.copiedDefaults.append(key)
            }
        }

        defaults.set(true, forKey: doneKey)
        return result
    }
}
