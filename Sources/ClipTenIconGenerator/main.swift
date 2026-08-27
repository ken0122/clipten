import AppKit
import ClipTenDesign

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Usage: ClipTenIconGenerator <AppIcon.iconset output directory>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    let image = ClipTenIcon.appIconImage(size: CGFloat(variant.pixels))
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        fputs("Could not render \(variant.name)\n", stderr)
        exit(1)
    }

    try pngData.write(to: outputDirectory.appendingPathComponent(variant.name))
}
