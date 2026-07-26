import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon <AppIcon.iconset>\n".utf8))
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func icon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let scale = CGFloat(size) / 1024
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    let outer = NSBezierPath(roundedRect: canvas.insetBy(dx: 52 * scale, dy: 52 * scale), xRadius: 220 * scale, yRadius: 220 * scale)
    NSColor(calibratedRed: 0.00, green: 0.17, blue: 0.21, alpha: 1).setFill()
    outer.fill()

    let glowRect = NSRect(x: 206 * scale, y: 206 * scale, width: 612 * scale, height: 612 * scale)
    let glow = NSBezierPath(ovalIn: glowRect)
    NSColor(calibratedRed: 0.71, green: 0.54, blue: 0.00, alpha: 1).setFill()
    glow.fill()

    NSColor.white.withAlphaComponent(0.96).setStroke()
    let viewfinder = NSBezierPath()
    viewfinder.lineWidth = 52 * scale
    viewfinder.lineCapStyle = .round
    let left = 350 * scale, right = 674 * scale, bottom = 350 * scale, top = 674 * scale
    let arm = 108 * scale
    viewfinder.move(to: NSPoint(x: left + arm, y: top))
    viewfinder.line(to: NSPoint(x: left, y: top))
    viewfinder.line(to: NSPoint(x: left, y: top - arm))
    viewfinder.move(to: NSPoint(x: right - arm, y: top))
    viewfinder.line(to: NSPoint(x: right, y: top))
    viewfinder.line(to: NSPoint(x: right, y: top - arm))
    viewfinder.move(to: NSPoint(x: left, y: bottom + arm))
    viewfinder.line(to: NSPoint(x: left, y: bottom))
    viewfinder.line(to: NSPoint(x: left + arm, y: bottom))
    viewfinder.move(to: NSPoint(x: right, y: bottom + arm))
    viewfinder.line(to: NSPoint(x: right, y: bottom))
    viewfinder.line(to: NSPoint(x: right - arm, y: bottom))
    viewfinder.stroke()

    let lens = NSBezierPath(ovalIn: NSRect(x: 437 * scale, y: 437 * scale, width: 150 * scale, height: 150 * scale))
    lens.lineWidth = 40 * scale
    lens.stroke()
    return image
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, size) in variants {
    guard let tiff = icon(size: size).tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: output.appendingPathComponent(name))
}
