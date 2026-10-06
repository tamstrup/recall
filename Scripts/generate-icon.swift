import AppKit

// Vector master: conversation lines inside a returning memory trace.
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets")
let iconset = destination.appendingPathComponent("Recall.iconset")
let catalog = destination.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    NSColor(calibratedRed: 0.16, green: 0.32, blue: 0.34, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 195, yRadius: 195).fill()
    NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.91, alpha: 1).setStroke()
    let path = NSBezierPath()
    path.lineWidth = 47
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: NSPoint(x: 675, y: 749))
    path.curve(to: NSPoint(x: 252, y: 508), controlPoint1: NSPoint(x: 434, y: 907), controlPoint2: NSPoint(x: 195, y: 754))
    path.curve(to: NSPoint(x: 712, y: 303), controlPoint1: NSPoint(x: 252, y: 242), controlPoint2: NSPoint(x: 510, y: 119))
    path.curve(to: NSPoint(x: 782, y: 514), controlPoint1: NSPoint(x: 784, y: 376), controlPoint2: NSPoint(x: 805, y: 445))
    path.move(to: NSPoint(x: 565, y: 749)); path.line(to: NSPoint(x: 675, y: 749)); path.line(to: NSPoint(x: 675, y: 859))
    path.stroke()
    let lines = NSBezierPath()
    lines.lineWidth = 39
    lines.lineCapStyle = .round
    for (y, end) in [(602.0, 594.0), (511, 641), (420, 545)] {
        lines.move(to: NSPoint(x: 402, y: y)); lines.line(to: NSPoint(x: end, y: y))
    }
    lines.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let data = render(points * scale)
        try data.write(to: iconset.appendingPathComponent(filename))
        try data.write(to: catalog.appendingPathComponent(filename))
        images.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: catalog.appendingPathComponent("Contents.json"))
try render(1024).write(to: destination.appendingPathComponent("Recall-1024.png"))
