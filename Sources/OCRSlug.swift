// ocr-slug.swift — on-device OCR (Apple Vision) → prints salient text for slugging.
// Usage: swift ocr-slug.swift <image-path>
// Prints the most prominent text lines (largest / highest-confidence first).
// Fully offline. No network, no API key.
import Foundation
import Vision
import AppKit

guard CommandLine.arguments.count > 1 else { exit(1) }
let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(1) }

let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = true

let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try? handler.perform([req])

// (text, confidence, box-height) — taller box ≈ bigger/more prominent text.
var lines: [(text: String, conf: Float, h: CGFloat)] = []
for obs in (req.results ?? []) {
    guard let c = obs.topCandidates(1).first else { continue }
    let s = c.string.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.count < 2 { continue }
    lines.append((s, c.confidence, obs.boundingBox.height))
}
// Prefer bigger text, then higher confidence.
let ranked = lines.sorted { ($0.h, $0.conf) > ($1.h, $1.conf) }
print(ranked.prefix(4).map { $0.text }.joined(separator: " "))
