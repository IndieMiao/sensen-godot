import AppKit
import ImageIO
import UniformTypeIdentifiers

// App Store icons must be opaque. Fill transparent pixels with the icon's
// existing center color, preserving all opaque artwork and pixel dimensions.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift flatten_app_icons.swift AppIcon.appiconset")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let files = try FileManager.default.contentsOfDirectory(at: directory,
                                                       includingPropertiesForKeys: nil)
for file in files where file.pathExtension.lowercased() == "png" {
    guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: file)),
          let image = bitmap.cgImage else {
        fatalError("Cannot read icon: \(file.path)")
    }
    if !bitmap.hasAlpha { continue }
    guard let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
        .usingColorSpace(NSColorSpace.deviceRGB),
          let context = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("Cannot create opaque icon bitmap")
    }
    context.setFillColor(red: center.redComponent, green: center.greenComponent,
                         blue: center.blueComponent, alpha: 1)
    let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.fill(bounds)
    context.draw(image, in: bounds)
    guard let opaqueImage = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(file as CFURL,
                                                            UTType.png.identifier as CFString,
                                                            1, nil) else {
        fatalError("Cannot write opaque icon")
    }
    CGImageDestinationAddImage(destination, opaqueImage, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Icon write failed") }
    print("Opaque icon: \(file.lastPathComponent)")
}
