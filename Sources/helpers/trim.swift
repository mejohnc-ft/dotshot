// trim.swift — trim a recording with the system trim controls (AVPlayerView) and export the kept range.
// Usage: trim <input> <output>
// Exit status: 0 = trimmed file written to <output>, 1 = cancelled, 2 = error.
// DOTSHOT_TRIM_RANGE=<start>,<end> (seconds) skips the window; tests use it to check the export.
// Replaces the QuickTime round trip, which saved trimmed copies somewhere dotshot never looked.
import AppKit
import AVFoundation
import AVKit

func stderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    stderr("usage: trim <input> <output>")
    exit(2)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let asset = AVURLAsset(url: input)

@available(macOS, deprecated: 15.0, message: "Only used before macOS 15")
func legacyExport(_ session: AVAssetExportSession) -> Never {
    session.outputURL = output
    session.outputFileType = .mov
    let semaphore = DispatchSemaphore(value: 0)
    session.exportAsynchronously { semaphore.signal() }
    semaphore.wait()
    if session.status == .completed { exit(0) }
    stderr("export failed: \(session.error?.localizedDescription ?? "unknown")")
    exit(2)
}

/// Copies the kept range without re-encoding.
func export(_ range: CMTimeRange) {
    guard range.duration.seconds > 0,
          let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
        stderr("nothing to export")
        exit(2)
    }
    try? FileManager.default.removeItem(at: output)
    session.timeRange = range
    if #available(macOS 15.0, *) {
        Task {
            do {
                try await session.export(to: output, as: .mov)
                exit(0)
            } catch {
                stderr("export failed: \(error.localizedDescription)")
                exit(2)
            }
        }
    } else {
        nonisolated(unsafe) let legacy = session
        DispatchQueue.global().async { legacyExport(legacy) }
    }
}

func seconds(_ value: Double) -> CMTime { CMTime(seconds: value, preferredTimescale: 600) }

if let range = ProcessInfo.processInfo.environment["DOTSHOT_TRIM_RANGE"] {
    let parts = range.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 2, parts[1] > parts[0] else {
        stderr("DOTSHOT_TRIM_RANGE must be <start>,<end>")
        exit(2)
    }
    export(CMTimeRange(start: seconds(parts[0]), end: seconds(parts[1])))
    dispatchMain()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
let playerView = AVPlayerView(frame: NSRect(x: 0, y: 0, width: 960, height: 600))
playerView.player = player
playerView.controlsStyle = .inline

let window = NSWindow(contentRect: playerView.frame, styleMask: [.titled, .closable, .resizable],
                      backing: .buffered, defer: false)
window.title = "Trim recording — drag the yellow handles, then click Trim"
window.contentView = playerView
window.level = .floating
// Excluded from screenshots and recordings like dotshot's other windows; DOTSHOT_CAPTURABLE=1 allows docs captures.
window.sharingType = ProcessInfo.processInfo.environment["DOTSHOT_CAPTURABLE"] == "1" ? .readOnly : .none
window.isReleasedWhenClosed = false
window.center()

final class CloseWatcher: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { exit(1) }
}
let closeWatcher = CloseWatcher()
window.delegate = closeWatcher

app.activate(ignoringOtherApps: true)
window.makeKeyAndOrderFront(nil)

// Trimming can begin once the player item is ready; give it a few seconds.
var attempts = 0
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
    attempts += 1
    guard playerView.canBeginTrimming else {
        if attempts > 100 {
            timer.invalidate()
            stderr("the recording could not be opened for trimming")
            exit(2)
        }
        return
    }
    timer.invalidate()
    playerView.beginTrimming { result in
        guard result == .okButton, let item = player.currentItem else { exit(1) }
        let start = item.reversePlaybackEndTime.isNumeric ? item.reversePlaybackEndTime : .zero
        let end = item.forwardPlaybackEndTime.isNumeric ? item.forwardPlaybackEndTime : item.duration
        window.delegate = nil
        window.orderOut(nil)
        export(CMTimeRange(start: start, end: end))
    }
}

app.run()
