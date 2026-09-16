// App.swift — the resident dotshot pill, recording picker, and guided setup.
// Collapsed = a small camera nub; hover expands to Shot / Vid, destinations, and recent captures.
import SwiftUI
import AppKit
import Carbon
import ServiceManagement
import QuickLookThumbnailing
import UniformTypeIdentifiers

let PATHS = Paths()

/// Documentation-capture switches. Never set in normal use.
struct DemoOptions {
    let capturable: Bool       // DOTSHOT_CAPTURABLE=1 lets screencapture see the pill
    let pinnedState: String?   // DOTSHOT_DEMO_STATE=collapsed|expanded|drop freezes the pill
    let suppressSetup: Bool    // DOTSHOT_NO_AUTO_SETUP=1 skips the automatic first-run window

    init(_ environment: [String: String] = ProcessInfo.processInfo.environment) {
        capturable = environment["DOTSHOT_CAPTURABLE"] == "1"
        pinnedState = environment["DOTSHOT_DEMO_STATE"]
        suppressSetup = environment["DOTSHOT_NO_AUTO_SETUP"] == "1"
    }
}
let DEMO = DemoOptions()
let SHOTS = PATHS.shots
let SCRIPT = Bundle.main.resourceURL?.appendingPathComponent("dotshot-capture.sh").path ?? ""

let COLLAPSED = NSSize(width: 56, height: 56)   // small round nub when idle
let EXPANDED  = NSSize(width: 500, height: 292)
let QUADRANT  = NSSize(width: 320, height: 224)
let RECORDING_PICKER = NSSize(width: 700, height: 390)

weak var pillWindow: NSWindow?

func configuredScreen() -> NSScreen? {
    let savedName = UserDefaults.standard.string(forKey: "dotshot.displayName")
    return savedName.flatMap { name in NSScreen.screens.first(where: { $0.localizedName == name }) }
        ?? NSScreen.main
        ?? NSScreen.screens.first
}

func configuredPillFrame(for size: NSSize) -> NSRect? {
    guard let visibleFrame = configuredScreen()?.visibleFrame else { return nil }
    let inset = CGFloat(UserDefaults.standard.double(forKey: "dotshot.inset"))
    let safeInset = UserDefaults.standard.object(forKey: "dotshot.inset") == nil ? 24 : min(max(inset, 0), 64)
    let position = UserDefaults.standard.string(forKey: "dotshot.position") ?? "bottomRight"

    let x = position.hasSuffix("Left")
        ? visibleFrame.minX + safeInset
        : visibleFrame.maxX - size.width - safeInset
    let y = position.hasPrefix("top")
        ? visibleFrame.maxY - size.height - safeInset
        : visibleFrame.minY + safeInset
    return NSRect(origin: NSPoint(x: x, y: y), size: size)
}

func resizePill(_ size: NSSize) {
    guard let window = pillWindow, let frame = configuredPillFrame(for: size) else { return }
    window.setFrame(frame, display: true, animate: true)
}

let HOTKEY_SIGNATURE: OSType = 0x44545348  // "DTSH"
let IMAGE_HOTKEY_ID: UInt32 = 1
let VIDEO_HOTKEY_ID: UInt32 = 2

final class DestinationStore: ObservableObject {
    static let shared = DestinationStore()
    @Published private(set) var items: [Destination] = []

    private init() { reload() }

    func reload() {
        guard let data = FileManager.default.contents(atPath: PATHS.destinationsFile),
              let text = String(data: data, encoding: .utf8) else {
            items = []
            return
        }
        items = DestinationFormat.parse(text)
    }

    @discardableResult
    func save(_ destinations: [Destination]) -> Bool {
        guard let cleaned = DestinationFormat.cleaned(destinations) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: PATHS.configDir),
                withIntermediateDirectories: true
            )
            try DestinationFormat.serialize(cleaned).write(
                to: URL(fileURLWithPath: PATHS.destinationsFile),
                atomically: true,
                encoding: .utf8
            )
            items = cleaned
            return true
        } catch {
            return false
        }
    }
}

/// The destination captures go to: `requested` when configured, else the saved choice, else the first.
/// Returns nil when nothing is configured.
func currentDestination(_ requested: String? = nil) -> String? {
    resolveDestination(
        requested: requested,
        saved: UserDefaults.standard.string(forKey: "dotshot.dest"),
        available: DestinationStore.shared.items.map(\.id)
    )
}

// One distinct color per destination tile (drop-mode quadrant).
let TILECOLORS: [Color] = [
    Color(red: 0.710, green: 0.537, blue: 0.000),  // gold
    Color(red: 0.165, green: 0.631, blue: 0.596),  // cyan
    Color(red: 0.424, green: 0.443, blue: 0.769),  // violet
    Color(red: 0.522, green: 0.600, blue: 0.000),  // green
]

// Accent presets — Solarized-forward, gold first (matches Solarized Dark bg). Persists across launches.
let PRESETS: [Color] = [
    Color(red: 0.710, green: 0.537, blue: 0.000),  // Solarized yellow  #b58900 (the classic gold)
    Color(red: 0.796, green: 0.627, blue: 0.165),  // brighter gold     #cba02a
    Color(red: 0.855, green: 0.706, blue: 0.286),  // pale amber gold   #dab449
    Color(red: 0.796, green: 0.294, blue: 0.086),  // Solarized orange  #cb4b16
    Color(red: 0.863, green: 0.196, blue: 0.184),  // Solarized red     #dc322f
    Color(red: 0.827, green: 0.212, blue: 0.510),  // Solarized magenta #d33682
    Color(red: 0.424, green: 0.443, blue: 0.769),  // Solarized violet  #6c71c4
    Color(red: 0.149, green: 0.545, blue: 0.824),  // Solarized blue    #268bd2
    Color(red: 0.165, green: 0.631, blue: 0.596),  // Solarized cyan    #2aa198
    Color(red: 0.522, green: 0.600, blue: 0.000),  // Solarized green   #859900
    Color(red: 0.170, green: 0.180, blue: 0.200),  // graphite
]

// Black or white text, whichever reads better on the given accent.
func idealText(on c: Color) -> Color {
    let ns = NSColor(c).usingColorSpace(.sRGB) ?? .white
    let lum = 0.299 * ns.redComponent + 0.587 * ns.greenComponent + 0.114 * ns.blueComponent
    return lum > 0.62 ? .black : .white
}

/// Runs the bundled capture script. Arguments are passed directly, never through a shell string.
func runScript(_ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [SCRIPT] + arguments
    do {
        try process.run()
    } catch {
        NSLog("dotshot: could not run capture script: \(error)")
        NSSound.beep()
    }
}

/// Opens setup instead of failing silently when no destination is configured yet.
func requireDestination(_ requested: String? = nil) -> String? {
    if let dest = currentDestination(requested) { return dest }
    NSSound.beep()
    SetupController.shared.present(initialStep: .destinations)
    return nil
}

func runCapture(_ mode: String, _ requested: String? = nil, _ extraArguments: [String] = []) {
    guard let dest = requireDestination(requested) else { return }
    runScript([mode, dest] + extraArguments)
}

struct RecordingSource: Identifiable {
    let id: String
    let screenNumber: Int?
    let name: String
    let resolution: String
    let aspectRatio: CGFloat
    let isMain: Bool

    static func available() -> [RecordingSource] {
        var sources = NSScreen.screens.enumerated().map { index, screen in
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { CGDirectDisplayID($0.uint32Value) }
            let mode = displayID.flatMap(CGDisplayCopyDisplayMode)
            let width = mode.map(\.pixelWidth) ?? Int(screen.frame.width)
            let height = mode.map(\.pixelHeight) ?? Int(screen.frame.height)
            return RecordingSource(
                id: "screen:\(index + 1)",
                screenNumber: index + 1,
                name: screen.localizedName,
                resolution: "\(width) × \(height)",
                aspectRatio: CGFloat(width) / CGFloat(max(height, 1)),
                isMain: index == 0
            )
        }
        sources.append(RecordingSource(
            id: "region",
            screenNumber: nil,
            name: "Selected Portion",
            resolution: "Drag any area",
            aspectRatio: 16 / 10,
            isMain: false
        ))
        return sources
    }
}

struct RecordingSourceCard: View {
    let source: RecordingSource
    let selected: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if source.screenNumber == nil {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundStyle(selected ? accent : Color.secondary.opacity(0.65))
                        .frame(width: 94, height: 58)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(selected ? accent : Color.secondary)
                } else {
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(
                                LinearGradient(
                                    colors: selected
                                        ? [accent.opacity(0.75), accent.opacity(0.30)]
                                        : [Color.secondary.opacity(0.28), Color.secondary.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(selected ? accent.opacity(0.95) : .white.opacity(0.22), lineWidth: 1)
                            )
                            .aspectRatio(source.aspectRatio, contentMode: .fit)
                            .frame(width: 98, height: 58)
                        Capsule()
                            .fill(selected ? accent.opacity(0.8) : Color.secondary.opacity(0.45))
                            .frame(width: 28, height: 3)
                    }
                }

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(idealText(on: accent), accent)
                        .background(Circle().fill(accent))
                        .offset(x: 54, y: -28)
                }
            }
            .frame(height: 66)

            VStack(spacing: 4) {
                Text(source.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(source.resolution)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if source.isMain {
                Text("MAIN")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(selected ? idealText(on: accent) : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(selected ? accent : Color.secondary.opacity(0.14), in: Capsule())
            } else {
                Color.clear.frame(height: 17)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(selected ? accent.opacity(0.13) : Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? accent : Color.primary.opacity(0.10), lineWidth: selected ? 2 : 1)
        )
    }
}

struct RecordingPickerView: View {
    let dest: String
    let sources: [RecordingSource]
    let onRecord: (RecordingSource) -> Void
    let onCancel: () -> Void

    @State private var selectedID: String
    @AppStorage("dotshot.accentIndex") private var accentIndex = 0
    private var accent: Color { PRESETS[min(max(accentIndex, 0), PRESETS.count - 1)] }
    private var selected: RecordingSource { sources.first(where: { $0.id == selectedID }) ?? sources[0] }

    init(dest: String, sources: [RecordingSource], onRecord: @escaping (RecordingSource) -> Void, onCancel: @escaping () -> Void) {
        self.dest = dest
        self.sources = sources
        self.onRecord = onRecord
        self.onCancel = onCancel
        let saved = UserDefaults.standard.string(forKey: "dotshot.recordingSource")
        let initial = sources.contains(where: { $0.id == saved }) ? saved! : (sources.first?.id ?? "region")
        _selectedID = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "record.circle")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(idealText(on: accent))
                    .frame(width: 44, height: 44)
                    .background(accent, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose what to record")
                        .font(.system(size: 20, weight: .bold))
                    Text("The finished recording will be named and sent to \(dest).")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .background(Color.primary.opacity(0.07), in: Circle())
            }

            HStack(spacing: 12) {
                ForEach(sources) { source in
                    Button {
                        selectedID = source.id
                    } label: {
                        RecordingSourceCard(source: source, selected: selectedID == source.id, accent: accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "stop.circle")
                    .foregroundStyle(.secondary)
                Text("Stop recording with ⌘⌃Esc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    UserDefaults.standard.set(selected.id, forKey: "dotshot.recordingSource")
                    onRecord(selected)
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .foregroundStyle(idealText(on: accent))
            }
        }
        .padding(28)
        .frame(width: RECORDING_PICKER.width - 28, height: RECORDING_PICKER.height - 28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.38), radius: 26, y: 12)
        .frame(width: RECORDING_PICKER.width, height: RECORDING_PICKER.height)
    }
}

final class RecordingPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class RecordingPickerController {
    static let shared = RecordingPickerController()
    private var panel: RecordingPickerPanel?

    func present(to dest: String) {
        let sources = RecordingSource.available()
        guard !sources.isEmpty else {
            NSSound.beep()
            return
        }

        panel?.close()
        let picker = RecordingPickerPanel(
            contentRect: NSRect(origin: .zero, size: RECORDING_PICKER),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        picker.isOpaque = false
        picker.backgroundColor = .clear
        picker.hasShadow = false
        picker.level = .floating
        picker.sharingType = .readOnly
        picker.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        picker.isReleasedWhenClosed = false

        picker.contentView = NSHostingView(rootView: RecordingPickerView(
            dest: dest,
            sources: sources,
            onRecord: { [weak self] source in
                self?.dismiss()
                if let screenNumber = source.screenNumber {
                    runCapture("video", dest, [String(screenNumber)])
                } else {
                    runCapture("video", dest)
                }
            },
            onCancel: { [weak self] in self?.dismiss() }
        ))

        let mouse = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        if let frame = targetScreen?.visibleFrame {
            picker.setFrameOrigin(NSPoint(
                x: frame.midX - RECORDING_PICKER.width / 2,
                y: frame.midY - RECORDING_PICKER.height / 2
            ))
        } else {
            picker.center()
        }

        panel = picker
        NSApp.activate(ignoringOtherApps: true)
        picker.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

func chooseRecordingSource(to requested: String? = nil) {
    guard let dest = requireDestination(requested) else { return }
    RecordingPickerController.shared.present(to: dest)
}

func runCaptureURL(_ url: URL) {
    switch parseCaptureURL(url, screenCount: NSScreen.screens.count) {
    case .image(let dest):
        runCapture("image", dest)
    case .videoDisplay(let dest, let screen):
        runCapture("video", dest, [String(screen)])
    case .videoRegion(let dest):
        runCapture("video", dest)
    case .videoPicker(let dest):
        chooseRecordingSource(to: dest)
    case .setup(let step):
        SetupController.shared.present(initialStep: step.flatMap(SetupStep.named) ?? .welcome)
    case .unknown:
        NSSound.beep()
    }
}

final class GlobalHotKeys {
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef?] = []

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HOTKEY_SIGNATURE else { return status }

                DispatchQueue.main.async {
                    if hotKeyID.id == VIDEO_HOTKEY_ID {
                        chooseRecordingSource()
                    } else {
                        runCapture("image")
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handler
        )

        // Global and permission-free: Control-Option-Command-S/V.
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        register(keyCode: UInt32(kVK_ANSI_S), modifiers: modifiers, id: IMAGE_HOTKEY_ID)
        register(keyCode: UInt32(kVK_ANSI_V), modifiers: modifiers, id: VIDEO_HOTKEY_ID)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HOTKEY_SIGNATURE, id: id)
        if RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr {
            keys.append(ref)
        }
    }

    deinit {
        for case let ref? in keys { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

func sendFile(_ path: String, to dest: String) {
    runScript(["send", dest, path])
}

// ── recent-shots gallery ─────────────────────────────────────────────────────
struct GItem: Identifiable {
    let id = UUID(); let url: URL; let name: String; var image: NSImage?
    var isVideo: Bool { ["mov","mp4","m4v"].contains(url.pathExtension.lowercased()) }
}
final class Gallery: ObservableObject {
    @Published var items: [GItem] = []
    func load() {
        let dir = URL(fileURLWithPath: SHOTS)
        let exts = ["png","jpg","jpeg","mov","mp4","m4v"]
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let media = files.filter { exts.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.hasPrefix(".") }
        let sorted = media.sorted {
            let a = (try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        items = sorted.prefix(10).map { GItem(url: $0, name: $0.lastPathComponent, image: nil) }
        for (i, it) in items.enumerated() { thumb(it.url, i) }
    }
    private func thumb(_ url: URL, _ idx: Int) {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 120, height: 74), scale: 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let ns = rep?.nsImage else { return }
            DispatchQueue.main.async { if idx < self.items.count { self.items[idx].image = ns } }
        }
    }
}

final class PillState: ObservableObject {
    @Published var expanded = true
    private var collapseWork: DispatchWorkItem?
    func hover(_ inside: Bool) {
        collapseWork?.cancel()
        if inside {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { expanded = true }
        } else {
            let w = DispatchWorkItem { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { self.expanded = false } }
            collapseWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
        }
    }
    func autoCollapse(after s: Double) {
        let w = DispatchWorkItem { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { self.expanded = false } }
        collapseWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
    }
}

struct BigButton: View {
    let title: String; let icon: String; let filled: Bool; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .tint(filled ? color : Color(nsColor: .controlColor))
        .foregroundStyle(filled ? idealText(on: color) : Color.primary)
    }
}

struct PillView: View {
    @StateObject private var state = PillState()
    @StateObject private var gallery = Gallery()
    @StateObject private var destinations = DestinationStore.shared
    @State private var copied = ""
    @AppStorage("dotshot.dest") private var dest = "work"
    @AppStorage("dotshot.accentIndex") private var accentIndex = 0
    private var accent: Color { PRESETS[min(max(accentIndex, 0), PRESETS.count - 1)] }
    @State private var dropMode = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if dropMode { quadrant }
            else if state.expanded { expanded }
            else { collapsed }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .onHover { if !dropMode && DEMO.pinnedState == nil { state.hover($0) } }
        .onDrop(of: [UTType.fileURL], isTargeted: Binding(
            get: { dropMode },
            set: { over in withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dropMode = over } }
        )) { providers, location in handleDrop(providers, at: location) }
        .onChange(of: state.expanded) { _, v in
            if !dropMode { resizePill(v ? EXPANDED : COLLAPSED); if v { gallery.load() } }
        }
        .onChange(of: dropMode) { _, v in
            resizePill(v ? QUADRANT : (state.expanded ? EXPANDED : COLLAPSED))
        }
        .onAppear {
            if !destinations.items.contains(where: { $0.id == dest }) {
                dest = destinations.items.first?.id ?? "work"
            }
            gallery.load()
            switch DEMO.pinnedState {
            case "collapsed":
                state.expanded = false
                resizePill(COLLAPSED)
            case "drop":
                dropMode = true
                resizePill(QUADRANT)
            case "expanded":
                resizePill(EXPANDED)
            default:
                resizePill(EXPANDED)
                state.autoCollapse(after: 6.0)
            }
        }
    }

    // Map the drop point to a quadrant → host, then ship each dropped file there.
    private func handleDrop(_ providers: [NSItemProvider], at loc: CGPoint) -> Bool {
        let col = loc.x < QUADRANT.width / 2 ? 0 : 1
        let row = loc.y < QUADRANT.height / 2 ? 0 : 1
        let dropDestinations = Array(destinations.items.prefix(4))
        let index = row * 2 + col
        guard index < dropDestinations.count else { return false }
        let host = dropDestinations[index].id
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let u = url { sendFile(u.path, to: host) }
            }
        }
        DispatchQueue.main.async { withAnimation { dropMode = false } }
        return true
    }

    var quadrant: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible())], spacing: 6) {
            ForEach(Array(destinations.items.prefix(4).enumerated()), id: \.element.id) { index, destination in
                tile(destination, colorIndex: index)
            }
        }
        .padding(10)
        .frame(width: QUADRANT.width, height: QUADRANT.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
    }

    func tile(_ destination: Destination, colorIndex: Int) -> some View {
        let color = TILECOLORS[colorIndex % TILECOLORS.count]
        return ZStack {
            RoundedRectangle(cornerRadius: 11).fill(color.opacity(0.92))
            VStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 19, weight: .semibold))
                Text(destination.id).font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(idealText(on: color))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var collapsed: some View {
        Image(systemName: "camera.viewfinder").font(.system(size: 17, weight: .bold))
            .foregroundStyle(idealText(on: accent))
            .frame(width: 42, height: 42)
            .background(
                Circle().fill(LinearGradient(colors: [accent, accent.opacity(0.80)],
                                             startPoint: .top, endPoint: .bottom))
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.40), radius: 9, y: 4)
            .frame(width: COLLAPSED.width, height: COLLAPSED.height)   // margin so the shadow isn't clipped
    }

    var expanded: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "camera.viewfinder").font(.system(size: 14, weight: .bold))
                Text("Shot →").font(.system(size: 15, weight: .bold))
                // Chromeless destination menu — looks like plain bold text, click to switch.
                Menu {
                    ForEach(destinations.items) { destination in
                        Button(destination.id) { dest = destination.id }
                    }
                } label: {
                    Text(destinations.items.isEmpty ? "setup required" : dest)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                Spacer()
                Button {
                    SetupController.shared.present(initialStep: .destinations)
                } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 13))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                Button { NSApp.terminate(nil) } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                BigButton(title: "Shot", icon: "camera.fill", filled: true,  color: accent) { runCapture("image", dest) }
                BigButton(title: "Vid",  icon: "video.fill",  filled: false, color: accent) { chooseRecordingSource(to: dest) }
            }
            .disabled(destinations.items.isEmpty)
            HStack(spacing: 8) {
                ForEach(Array(PRESETS.enumerated()), id: \.offset) { i, c in
                    Circle().fill(c).frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
                        .overlay(Circle().strokeBorder(.white, lineWidth: accentIndex == i ? 2 : 0))
                        .contentShape(Circle())
                        .onTapGesture { accentIndex = i }
                }
                Spacer()
                Text("⌃⌥⌘S Shot  ·  ⌃⌥⌘V Vid")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if !gallery.items.isEmpty {
                Text(copied.isEmpty ? "RECENT — click to copy name" : "Copied \(copied)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(copied.isEmpty ? Color.secondary : accent)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(gallery.items) { it in
                            ZStack {
                                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.14))
                                if let img = it.image {
                                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                        .frame(width: 104, height: 66).clipped()
                                } else { ProgressView().controlSize(.small) }
                                if it.isVideo {
                                    Image(systemName: "play.circle.fill").font(.system(size: 17))
                                        .foregroundStyle(.white.opacity(0.92)).shadow(radius: 2)
                                }
                                if copied == it.name {
                                    RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.42))
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(.white)
                                }
                            }
                            .frame(width: 104, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.12)))
                            .help(it.name)
                            .onTapGesture {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(it.name, forType: .string)
                                copied = it.name
                            }
                        }
                    }
                }
                .frame(height: 72)
            }
        }
        .padding(16)
        .frame(width: EXPANDED.width, height: EXPANDED.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
    }
}

enum SetupStep: Int, CaseIterable, Identifiable {
    case welcome, permissions, connect, destinations, test, login, appearance, done

    var id: Int { rawValue }
    static func named(_ name: String) -> SetupStep? {
        allCases.first { String(describing: $0) == name.lowercased() }
    }
    var title: String {
        switch self {
        case .welcome: "Why dotshot"
        case .permissions: "Permission"
        case .connect: "Connect Devices"
        case .destinations: "Destinations"
        case .test: "First Capture"
        case .login: "Launch at Login"
        case .appearance: "Appearance"
        case .done: "Done"
        }
    }
    var icon: String {
        switch self {
        case .welcome: "sparkles"
        case .permissions: "rectangle.inset.filled.and.person.filled"
        case .connect: "key.horizontal"
        case .destinations: "network"
        case .test: "checkmark.circle"
        case .login: "power"
        case .appearance: "paintpalette"
        case .done: "flag.checkered"
        }
    }
}

struct SetupView: View {
    let initialStep: SetupStep
    let onFinish: () -> Void

    @State private var step: SetupStep
    @State private var draftDestinations: [Destination]
    @State private var testStatus: [Int: String] = [:]
    @State private var saveMessage = ""
    @State private var screenPermission = CGPreflightScreenCaptureAccess()
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginMessage = ""
    @State private var sshSetupMessage = ""
    @State private var sshRefreshToken = 0
    @AppStorage("dotshot.accentIndex") private var accentIndex = 0
    @AppStorage("dotshot.position") private var position = "bottomRight"
    @AppStorage("dotshot.displayName") private var displayName = ""
    @AppStorage("dotshot.inset") private var inset = 24.0

    private var accent: Color { PRESETS[min(max(accentIndex, 0), PRESETS.count - 1)] }
    private var publicKeyURL: URL? {
        _ = sshRefreshToken
        let sshDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".ssh", isDirectory: true)
        return ["id_ed25519.pub", "id_ecdsa.pub", "id_rsa.pub"]
            .map { sshDirectory.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    init(initialStep: SetupStep, onFinish: @escaping () -> Void) {
        self.initialStep = initialStep
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
        let existing = DestinationStore.shared.items
        _draftDestinations = State(initialValue: existing.isEmpty
            ? [Destination(id: "work", host: "", remotePath: "~/inbound")]
            : existing)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                ScrollView {
                    stepContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(34)
                }
                Divider()
                footer
                    .padding(.horizontal, 30)
                    .padding(.vertical, 18)
            }
        }
        .frame(width: 840, height: 610)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14)))
        .overlay(alignment: .topTrailing) {
            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 25, height: 25)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
            .padding(18)
        }
        .shadow(color: .black.opacity(0.4), radius: 28, y: 14)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(idealText(on: accent))
                    .frame(width: 34, height: 34)
                    .background(accent, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text("dotshot").font(.system(size: 15, weight: .bold))
                    Text("SETUP · v\(Brand.version)").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)

            ForEach(SetupStep.allCases) { item in
                Button {
                    step = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .frame(width: 18)
                        Text(item.title)
                            .font(.system(size: 12.5, weight: step == item ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer()
                        if item.rawValue < step.rawValue {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(accent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(step == item ? accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(step == item ? Color.primary : Color.secondary)
            }
            Spacer()
            Text("Settings can be reopened from the gear on the expanded pill.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 210)
        .background(Color.black.opacity(0.10))
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .permissions:
            permissionStep
        case .connect:
            connectStep
        case .destinations:
            destinationsStep
        case .test:
            testStep
        case .login:
            loginStep
        case .appearance:
            appearanceStep
        case .done:
            doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            setupHeading(
                "Capture here. Let your agents use it there.",
                "dotshot delivers visual context from this Mac to every machine in your coding fleet—without uploads, inboxes, or broken focus."
            )
            HStack(spacing: 12) {
                flowCard("1", "Capture", "Take a screenshot or recording from any app.", "camera.viewfinder")
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.tertiary)
                flowCard("2", "Deliver", "dotshot names it and sends it over SSH.", "paperplane.fill")
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.tertiary)
                flowCard("3", "Use", "The remote path is copied, ready for your agent.", "terminal.fill")
            }
            callout(
                "Private by design",
                "Files travel through your existing SSH or Tailscale connection. There is no dotshot account, cloud inbox, receiving service, telemetry, or API key.",
                "lock.shield.fill"
            )
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            setupHeading("Allow Screen Recording", "macOS protects screen contents. This permission is required for screenshots and recordings.")
            HStack(spacing: 14) {
                Image(systemName: screenPermission ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 34))
                    .foregroundStyle(screenPermission ? Color.green : accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(screenPermission ? "Permission granted" : "Permission still needed")
                        .font(.system(size: 16, weight: .semibold))
                    Text(screenPermission
                        ? "dotshot can capture your selected screen content."
                        : "Approve dotshot in Privacy & Security → Screen & System Audio Recording.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))

            HStack {
                Button("Request Permission") {
                    _ = CGRequestScreenCaptureAccess()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        screenPermission = CGPreflightScreenCaptureAccess()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                Button("Check Again") {
                    screenPermission = CGPreflightScreenCaptureAccess()
                }
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Text("macOS may ask you to quit and reopen dotshot after approval. If the status does not change, relaunch dotshot and press Check Again.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            setupHeading(
                "Connect this Mac to your other devices",
                "dotshot uses normal SSH key authentication. You do not need an SSH alias, Tailscale, a server, or a dotshot account."
            )

            HStack(alignment: .top, spacing: 12) {
                completionCard(
                    "1. Enable SSH",
                    "Mac: enable Settings → General → Sharing → Remote Login. Linux: enable the OpenSSH server.",
                    "switch.2"
                )
                completionCard(
                    "2. Prepare a key",
                    publicKeyURL == nil
                        ? "Create an Ed25519 key on this Mac. A public key identifies this Mac; your private key never leaves it."
                        : "A public key is ready on this Mac: \(publicKeyURL?.lastPathComponent ?? "")",
                    publicKeyURL == nil ? "key" : "checkmark.seal.fill"
                )
                completionCard(
                    "3. Authorize it",
                    "Install this Mac’s public key once. dotshot can then transfer without password prompts.",
                    "person.badge.key.fill"
                )
            }

            HStack(spacing: 10) {
                if publicKeyURL == nil {
                    Button("Copy Key Creation Command") {
                        copyToClipboard(
                            "ssh-keygen -t ed25519 -C \"dotshot@\(Host.current().localizedName ?? "mac")\"",
                            confirmation: "Key creation command copied"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                } else {
                    Button("Copy Public Key") {
                        copyPublicKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                }
                Button("Open Terminal") { openTerminal() }
                Button("Refresh") {
                    sshRefreshToken += 1
                    sshSetupMessage = publicKeyURL == nil ? "No standard public key found yet" : "Public key detected"
                }
                Text(sshSetupMessage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(sshSetupMessage.contains("couldn’t") ? Color.orange : Color.green)
            }

            callout(
                "No alias required",
                "On the next screen, enter a direct address such as john@mac-studio.local, john@100.64.0.10, or john@mac-studio. An existing ~/.ssh/config alias works too.",
                "network"
            )
            Text("Tailscale: use the destination’s MagicDNS name or 100.x address. Both devices must share a tailnet, with regular SSH or Tailscale SSH enabled on the destination.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Text("Next, enter the address and press Test. If the key is rejected, dotshot offers an authorization command that asks for the destination password once.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    private var destinationsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupHeading(
                "Choose where captures should land",
                "Give each device a short name, its SSH address, and a receiving folder. A direct username@hostname works—aliases are optional."
            )
            VStack(spacing: 10) {
                HStack {
                    Text("NAME").frame(width: 90, alignment: .leading)
                    Text("SSH ADDRESS OR ALIAS").frame(maxWidth: .infinity, alignment: .leading)
                    Text("DESTINATION FOLDER").frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 76)
                }
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

                ForEach(draftDestinations.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        TextField("work", text: $draftDestinations[index].id)
                            .frame(width: 90)
                        TextField("john@mac-studio.local", text: $draftDestinations[index].host)
                        TextField("~/inbound", text: $draftDestinations[index].remotePath)
                        Button {
                            testDestination(at: index)
                        } label: {
                            if testStatus[index] == "Testing…" {
                                ProgressView().controlSize(.small).frame(width: 52)
                            } else {
                                Text("Test").frame(width: 52)
                            }
                        }
                        .disabled(draftDestinations[index].host.isEmpty || draftDestinations[index].remotePath.isEmpty)
                        Button {
                            draftDestinations.remove(at: index)
                            testStatus = [:]  // statuses are keyed by row index
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(draftDestinations.count == 1)
                    }
                    .textFieldStyle(.roundedBorder)
                    if let status = testStatus[index] {
                        HStack {
                            if !status.hasPrefix("Ready"), status != "Testing…", publicKeyURL != nil,
                               draftDestinations.indices.contains(index), !draftDestinations[index].host.isEmpty {
                                Button("Copy key authorization command") {
                                    copyAuthorizationCommand(for: draftDestinations[index])
                                }
                                .buttonStyle(.link)
                                .font(.system(size: 10.5))
                            }
                            Spacer()
                            Text(status)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(status.hasPrefix("Ready") ? Color.green : (status == "Testing…" ? Color.secondary : Color.orange))
                        }
                    }
                }
            }

            HStack {
                Button("SSH setup help") { step = .connect }
                Button {
                    draftDestinations.append(Destination(id: "device\(draftDestinations.count + 1)", host: "", remotePath: "~/inbound"))
                } label: {
                    Label("Add destination", systemImage: "plus")
                }
                Spacer()
                if !saveMessage.isEmpty {
                    Text(saveMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(saveMessage == "Saved" ? Color.green : Color.orange)
                }
                Button("Save") { saveDestinations() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
            callout(
                "Test before continuing",
                "Test checks the host, key authentication, and folder separately. It creates the folder when allowed and converts ~/inbound into an absolute path your agent can use.",
                "checkmark.shield.fill"
            )
        }
    }

    private var testStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            setupHeading("Complete your first capture", "This is the whole dotshot loop: capture here, deliver there, then give the copied path to your agent.")
            VStack(alignment: .leading, spacing: 14) {
                tutorialRow("1", "Press ⌃⌥⌘S from any app—or click the button below.")
                tutorialRow("2", "Drag around a harmless test area, then release.")
                tutorialRow("3", "Wait for “Sent.” dotshot names the image and copies its remote path.")
                tutorialRow("4", "In your agent, paste the path with a request such as “Review this screenshot.”")
            }
            HStack {
                Button {
                    saveDestinations()
                    runCapture("image")
                } label: {
                    Label("Take Test Shot", systemImage: "camera.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                Button("Open Local Shots") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: SHOTS))
                }
            }
            callout(
                "The payoff",
                "No save dialog, manual filename, upload, or hunt for the file. Your agent gets a path it can read on the machine where it is already working.",
                "wand.and.stars"
            )
            callout("Recording shortcut", "Press ⌃⌥⌘V. Choose a full display or Selected Portion, then stop with ⌘⌃Esc.", "video.fill")
        }
    }

    private var loginStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            setupHeading("Launch at Login", "Register dotshot with macOS so the camera nub is ready after every sign-in.")
            HStack(spacing: 14) {
                Image(systemName: loginStatus == .enabled ? "checkmark.circle.fill" : "power")
                    .font(.system(size: 34))
                    .foregroundStyle(loginStatus == .enabled ? Color.green : accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(loginStatusText).font(.system(size: 16, weight: .semibold))
                    Text("macOS keeps the final approval under System Settings → General → Login Items.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))

            HStack {
                Button(loginStatus == .enabled ? "Disable Launch at Login" : "Enable Launch at Login") {
                    updateLoginItem(enable: loginStatus != .enabled)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                Button("Open Login Items") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            if !loginMessage.isEmpty {
                Text(loginMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var appearanceStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            setupHeading("Make it yours", "Choose the accent, display, corner, and edge inset for the collapsed camera nub.")
            VStack(alignment: .leading, spacing: 10) {
                Text("ACCENT").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(Array(PRESETS.enumerated()), id: \.offset) { index, color in
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(.white, lineWidth: accentIndex == index ? 3 : 0))
                            .shadow(color: .black.opacity(0.18), radius: 2)
                            .onTapGesture { accentIndex = index }
                    }
                }
            }
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("DISPLAY").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                    Picker("", selection: $displayName) {
                        ForEach(NSScreen.screens, id: \.localizedName) { screen in
                            Text(screen.localizedName).tag(screen.localizedName)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 230)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("CORNER").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        cornerButton("topLeft", "arrow.up.left")
                        cornerButton("topRight", "arrow.up.right")
                        cornerButton("bottomLeft", "arrow.down.left")
                        cornerButton("bottomRight", "arrow.down.right")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("EDGE INSET").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(inset)) px").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                Slider(value: $inset, in: 0...48, step: 2)
            }
            .onChange(of: inset) { _, _ in repositionPill() }
            .onChange(of: displayName) { _, _ in repositionPill() }
            .onChange(of: position) { _, _ in repositionPill() }
        }
        .onAppear {
            if displayName.isEmpty { displayName = configuredScreen()?.localizedName ?? "" }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            setupHeading("Your visual context pipeline is ready", "The camera nub stays out of the way until you hover, use a shortcut, or drag a file onto it.")
            VStack(alignment: .leading, spacing: 14) {
                summaryRow("Screenshot", "⌃⌥⌘S", "camera.fill")
                summaryRow("Screen recording", "⌃⌥⌘V", "video.fill")
                summaryRow("Automation", "dotshot://image?dest=work", "link")
                summaryRow("Settings", "Hover → gear", "gearshape.fill")
            }
            callout("One privacy reminder", "Captures may contain sensitive information. dotshot saves a local copy in ~/Shots and transfers only to destinations you configure.", "hand.raised.fill")
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    if let previous = SetupStep(rawValue: step.rawValue - 1) { step = previous }
                }
            }
            Spacer()
            Text("\(step.rawValue + 1) of \(SetupStep.allCases.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Button(step == .done ? "Finish" : "Continue") { advance() }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func setupHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 25, weight: .bold))
            Text(subtitle).font(.system(size: 13.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func flowCard(_ number: String, _ title: String, _ subtitle: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(number)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(idealText(on: accent))
                    .frame(width: 22, height: 22)
                    .background(accent, in: Circle())
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(title).font(.system(size: 14.5, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private func completionCard(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(accent)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private func callout(_ title: String, _ text: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func tutorialRow(_ number: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(idealText(on: accent))
                .frame(width: 25, height: 25)
                .background(accent, in: Circle())
            Text(text).font(.system(size: 13))
        }
    }

    private func summaryRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(accent).frame(width: 24)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func cornerButton(_ value: String, _ icon: String) -> some View {
        Button {
            position = value
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 30)
                .background(position == value ? accent : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(position == value ? idealText(on: accent) : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private var loginStatusText: String {
        switch loginStatus {
        case .enabled: "Launch at Login is enabled"
        case .requiresApproval: "Approval is required in System Settings"
        case .notFound: "macOS could not find this app"
        default: "Launch at Login is off"
        }
    }

    private func advance() {
        if step == .destinations {
            guard saveDestinations() else { return }
            if !UserDefaults.standard.bool(forKey: "dotshot.onboardingComplete"),
               !testStatus.values.contains(where: { $0.hasPrefix("Ready") }) {
                saveMessage = "Test at least one destination to complete first-time setup"
                return
            }
        }
        if step == .done {
            UserDefaults.standard.set(true, forKey: "dotshot.onboardingComplete")
            DestinationStore.shared.reload()
            onFinish()
            return
        }
        if let next = SetupStep(rawValue: step.rawValue + 1) { step = next }
    }

    @discardableResult
    private func saveDestinations() -> Bool {
        let saved = DestinationStore.shared.save(draftDestinations)
        saveMessage = saved
            ? "Saved"
            : "Use unique one-word names, a host without spaces, and an absolute or ~/ folder"
        if saved {
            let current = currentDestination() ?? ""
            UserDefaults.standard.set(current, forKey: "dotshot.dest")
        }
        return saved
    }

    private func testDestination(at index: Int) {
        guard draftDestinations.indices.contains(index) else { return }
        let destination = draftDestinations[index]
        guard !destination.host.isEmpty,
              !destination.host.hasPrefix("-"),
              destination.host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            testStatus[index] = "Invalid address — use username@hostname or an SSH alias"
            return
        }
        guard destination.remotePath == "~"
                || destination.remotePath.hasPrefix("~/")
                || destination.remotePath.hasPrefix("/") else {
            testStatus[index] = "Invalid folder — use an absolute path or ~/folder"
            return
        }
        testStatus[index] = "Testing…"
        let targetExpression = remotePathExpression(destination.remotePath)
        let remoteCommand = """
        target=\(targetExpression)
        mkdir -p "$target" || exit 20
        test -d "$target" || exit 21
        test -w "$target" || exit 22
        cd "$target" && pwd -P
        """

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = [
                "-o", "BatchMode=yes",
                "-o", "NumberOfPasswordPrompts=0",
                "-o", "ConnectTimeout=7",
                destination.host,
                remoteCommand
            ]
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolvedPath = detail
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .last(where: { $0.hasPrefix("/") })
                let result = destinationTestMessage(
                    status: process.terminationStatus,
                    detail: detail,
                    resolvedPath: resolvedPath
                )
                DispatchQueue.main.async {
                    guard draftDestinations.indices.contains(index),
                          draftDestinations[index].host == destination.host else { return }
                    if process.terminationStatus == 0, let resolvedPath {
                        draftDestinations[index].remotePath = resolvedPath
                    }
                    testStatus[index] = result
                }
            } catch {
                DispatchQueue.main.async { testStatus[index] = "Failed — \(error.localizedDescription)" }
            }
        }
    }

    private func destinationTestMessage(status: Int32, detail: String, resolvedPath: String?) -> String {
        if status == 0 {
            return "Ready — connected; \(resolvedPath ?? "folder") is writable"
        }
        switch status {
        case 20:
            return "Folder blocked — it could not be created with this account"
        case 21:
            return "Folder invalid — the path exists but is not a directory"
        case 22:
            return "Folder read-only — choose a path this account can write to"
        default:
            break
        }

        let message = detail.lowercased()
        if message.contains("could not resolve hostname")
            || message.contains("nodename nor servname provided") {
            return "Host not found — check the device name, IP address, or SSH alias"
        }
        if message.contains("operation timed out") || message.contains("connection timed out") {
            return "Timed out — check that the device is online and reachable"
        }
        if message.contains("connection refused") {
            return "SSH is off — enable Remote Login or the OpenSSH server"
        }
        if message.contains("permission denied") || message.contains("no supported authentication methods") {
            return "Key rejected — authorize this Mac’s public key on the destination"
        }
        if message.contains("host key verification failed") {
            return "Identity check needed — connect once with ssh in Terminal"
        }
        if message.contains("remote host identification has changed") {
            return "Host identity changed — review the warning in Terminal before continuing"
        }
        if message.contains("no route to host") || message.contains("network is unreachable") {
            return "Device unreachable — check its network or Tailscale connection"
        }
        return "Connection failed — try ssh \(detail.isEmpty ? "in Terminal for details" : "to this device in Terminal")"
    }

    private func remotePathExpression(_ path: String) -> String {
        if path == "~" { return "\"$HOME\"" }
        if path.hasPrefix("~/") {
            return "\"$HOME\"/" + shellSingleQuote(String(path.dropFirst(2)))
        }
        return shellSingleQuote(path)
    }

    private func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func copyPublicKey() {
        guard let publicKeyURL,
              let key = try? String(contentsOf: publicKeyURL, encoding: .utf8) else {
            sshSetupMessage = "Public key couldn’t be read"
            return
        }
        copyToClipboard(key.trimmingCharacters(in: .whitespacesAndNewlines), confirmation: "Public key copied")
    }

    private func copyAuthorizationCommand(for destination: Destination) {
        guard let publicKeyURL else {
            sshSetupMessage = "Create an SSH key first"
            step = .connect
            return
        }
        let command = "cat \(shellSingleQuote(publicKeyURL.path)) | ssh \(shellSingleQuote(destination.host)) 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'"
        copyToClipboard(command, confirmation: "Authorization command copied—run it in Terminal")
    }

    private func copyToClipboard(_ value: String, confirmation: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        sshSetupMessage = confirmation
    }

    private func openTerminal() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal"]
        do {
            try process.run()
        } catch {
            sshSetupMessage = "Terminal couldn’t be opened"
        }
    }

    private func updateLoginItem(enable: Bool) {
        do {
            if enable {
                if SMAppService.mainApp.status == .notRegistered {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginMessage = ""
        } catch {
            loginMessage = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
    }

    private func repositionPill() {
        if let currentSize = pillWindow?.frame.size { resizePill(currentSize) }
    }
}

final class SetupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SetupController {
    static let shared = SetupController()
    private var panel: SetupPanel?

    func present(initialStep: SetupStep = .welcome) {
        panel?.close()
        let size = NSSize(width: 868, height: 638)
        let setupPanel = SetupPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setupPanel.isOpaque = false
        setupPanel.backgroundColor = .clear
        setupPanel.hasShadow = false
        setupPanel.level = .floating
        setupPanel.sharingType = .readOnly
        setupPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setupPanel.isReleasedWhenClosed = false
        setupPanel.contentView = NSHostingView(rootView: SetupView(
            initialStep: initialStep,
            onFinish: { [weak self] in self?.dismiss() }
        ))
        setupPanel.center()
        panel = setupPanel
        NSApp.activate(ignoringOtherApps: true)
        setupPanel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSPanel!
    var globalHotKeys: GlobalHotKeys!

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        globalHotKeys = GlobalHotKeys()
        let host = NSHostingView(rootView: PillView())
        window = NSPanel(contentRect: NSRect(origin: .zero, size: EXPANDED),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.contentView = host
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Excluded from screenshots & recordings, except when capturing documentation images.
        window.sharingType = DEMO.capturable ? .readOnly : .none
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        if let frame = configuredPillFrame(for: EXPANDED) {
            window.setFrame(frame, display: true)
        }
        pillWindow = window
        window.makeKeyAndOrderFront(nil)

        if !DEMO.suppressSetup,
           !UserDefaults.standard.bool(forKey: "dotshot.onboardingComplete")
            || DestinationStore.shared.items.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SetupController.shared.present(initialStep: .welcome)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(runCaptureURL)
    }
}
