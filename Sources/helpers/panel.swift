// panel.swift — small native prompt used by dotshot-capture.sh, with a recent-captures gallery.
// Usage: swift panel.swift "<title>" "<message>" <showField:0|1> "<Btn1,Btn2,...>" "<galleryDir|-> "
// Prints: "<clicked-button-lowercased>\t<field-text>"   (Esc / close → "cancel\t")
// Clicking a gallery thumbnail copies that file's name to the clipboard (does not dismiss).
import SwiftUI
import AppKit
import QuickLookThumbnailing

let args = CommandLine.arguments
let pTitle    = args.count > 1 ? args[1] : "dotshot"
let pMessage  = args.count > 2 ? args[2] : ""
let pShowField = (args.count > 3 ? args[3] : "0") == "1"
let pButtons  = (args.count > 4 ? args[4] : "OK").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
let pGalleryDir = args.count > 5 ? args[5] : "-"
let pDests    = (args.count > 6 && args[6] != "-") ? args[6].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } : []

func emit(_ button: String, _ name: String, _ dest: String) -> Never {
    FileHandle.standardOutput.write((button.lowercased() + "\t" + name + "\t" + dest + "\n").data(using: .utf8)!)
    exit(0)
}

struct GItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    var image: NSImage?
    var isVideo: Bool { ["mov","mp4","m4v"].contains(url.pathExtension.lowercased()) }
}

final class Gallery: ObservableObject {
    @Published var items: [GItem] = []
    func load(_ dirPath: String) {
        guard dirPath != "-" else { return }
        let dir = URL(fileURLWithPath: (dirPath as NSString).expandingTildeInPath)
        let fm = FileManager.default
        let exts = ["png","jpg","jpeg","mov","mp4","m4v"]
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let media = files.filter { exts.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.hasPrefix(".") }
        let sorted = media.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        items = sorted.prefix(10).map { GItem(url: $0, name: $0.lastPathComponent, image: nil) }
        for (i, it) in items.enumerated() { thumb(it.url, i) }
    }
    private func thumb(_ url: URL, _ idx: Int) {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 128, height: 82), scale: 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let ns = rep?.nsImage else { return }
            DispatchQueue.main.async { if idx < self.items.count { self.items[idx].image = ns } }
        }
    }
}

struct PanelView: View {
    let title: String
    let message: String
    let showField: Bool
    let buttons: [String]
    let galleryDir: String
    let dests: [String]
    @State private var name = ""
    @State private var copied = ""
    @State private var selectedDest = ""
    @FocusState private var focused: Bool
    @StateObject private var gallery = Gallery()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 22, weight: .bold))
            if !message.isEmpty {
                Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if showField {
                TextField("Name (optional — blank = auto-name)", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.secondary.opacity(0.35)))
                    .focused($focused)
                    .onSubmit { emit(buttons.first ?? "ok", name, selectedDest) }
            }
            if !dests.isEmpty {
                HStack(spacing: 8) {
                    Text("Send to").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Picker("", selection: $selectedDest) {
                        ForEach(dests, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize().controlSize(.large)
                    Spacer()
                }
            }
            HStack(spacing: 10) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { idx, b in
                    Button(action: { emit(b, name, selectedDest) }) {
                        Text(b).font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(idx == 0 ? .accentColor : Color(nsColor: .controlColor))
                    .foregroundStyle(idx == 0 ? Color.white : Color.primary)
                    .keyboardShortcut(idx == 0 ? .defaultAction : .init(KeyEquivalent(Character("\(idx+1)"))))
                }
            }
            if !gallery.items.isEmpty {
                Divider().padding(.top, 2)
                Text(copied.isEmpty ? "RECENT — click to copy name" : "Copied \(copied)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(copied.isEmpty ? Color.secondary : Color.accentColor)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(gallery.items) { it in
                            ZStack {
                                RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.12))
                                if let img = it.image {
                                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                        .frame(width: 116, height: 74).clipped()
                                } else {
                                    ProgressView().controlSize(.small)
                                }
                                if it.isVideo {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 20)).foregroundStyle(.white.opacity(0.92))
                                        .shadow(radius: 2)
                                }
                                if copied == it.name {
                                    RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.4))
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(.white)
                                }
                            }
                            .frame(width: 116, height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.25)))
                            .help(it.name)
                            .onTapGesture { copy(it.name) }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 80)
            }
            HStack {
                Spacer()
                Button("Cancel") { emit("cancel", "", "") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear {
            if selectedDest.isEmpty { selectedDest = dests.first ?? "" }
            gallery.load(galleryDir)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
    }

    private func copy(_ n: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(n, forType: .string)
        copied = n
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let hosting = NSHostingController(rootView: PanelView(title: pTitle, message: pMessage, showField: pShowField, buttons: pButtons, galleryDir: pGalleryDir, dests: pDests))
let window = NSWindow(contentViewController: hosting)
window.styleMask = [.titled, .fullSizeContentView]
window.titlebarAppearsTransparent = true
window.titleVisibility = .hidden
// Excluded from screenshots & screen recordings; DOTSHOT_CAPTURABLE=1 allows docs captures.
window.sharingType = ProcessInfo.processInfo.environment["DOTSHOT_CAPTURABLE"] == "1" ? .readOnly : .none
window.isMovableByWindowBackground = true
window.center()
window.makeKeyAndOrderFront(nil)
window.level = .floating
app.activate(ignoringOtherApps: true)
app.run()
