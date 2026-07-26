// avresize.swift — resize/re-encode a video to a smaller preset via AVFoundation.
// Usage: swift avresize.swift <input> <output> [presetName]
// Default preset: AVAssetExportPreset1280x720. No external deps (no ffmpeg).
import Foundation
import AVFoundation

func stderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func legacyExport(_ session: AVAssetExportSession, to output: URL) -> Never {
    session.outputURL = output
    session.outputFileType = .mov
    let semaphore = DispatchSemaphore(value: 0)
    session.exportAsynchronously { semaphore.signal() }
    semaphore.wait()
    if session.status == .completed { exit(0) }
    stderr("export failed: \(session.error?.localizedDescription ?? "unknown")")
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    stderr("usage: avresize <in> <out> [preset]")
    exit(2)
}

let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let preset = arguments.count > 3 ? arguments[3] : AVAssetExportPreset1280x720
let asset = AVURLAsset(url: input)
guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
    stderr("could not create export session for preset \(preset)")
    exit(3)
}

try? FileManager.default.removeItem(at: output)
session.shouldOptimizeForNetworkUse = true

if #available(macOS 15.0, *) {
    Task {
        do {
            try await session.export(to: output, as: .mov)
            exit(0)
        } catch {
            stderr("export failed: \(error.localizedDescription)")
            exit(1)
        }
    }
    dispatchMain()
} else {
    legacyExport(session, to: output)
}
