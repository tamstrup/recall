import AppKit
import ImageIO

// Preserve the approved artwork; only resample it into macOS's required sizes.
// Usage from the repository root: swift Scripts/generate-icon.swift Assets
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets")
let sourceURL = destination.appendingPathComponent("IconSource/Recall.png")
let iconset = destination.appendingPathComponent("Recall.iconset")
let catalog = destination.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      artwork.width == artwork.height, artwork.width >= 1024 else {
    fatalError("The approved source must be a square PNG at least 1024 pixels wide: \(sourceURL.path)")
}
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)

func render(_ size: Int) throws -> Data {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "RecallIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create icon bitmap."])
    }
    context.interpolationQuality = .high
    context.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let image = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "RecallIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot encode icon PNG."])
    }
    return data
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let data = try render(points * scale)
        try data.write(to: iconset.appendingPathComponent(filename), options: .atomic)
        try data.write(to: catalog.appendingPathComponent(filename), options: .atomic)
        images.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: catalog.appendingPathComponent("Contents.json"), options: .atomic)
try render(1024).write(to: destination.appendingPathComponent("Recall-1024.png"), options: .atomic)
print("Generated all ten macOS icon variants and the 1024 px master from the approved artwork.")
