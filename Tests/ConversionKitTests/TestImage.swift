import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Fixtures are generated at test time rather than checked in as binaries:
/// exact pixel dimensions, no repository weight, and no drift between the
/// fixture and what the test claims about it.
enum TestImage {
    /// A unique scratch directory per test. Nothing here is ever deleted by
    /// this project — the OS reclaims its own temp space.
    static func scratchDirectory(_ label: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ImageDropTests-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writePNG(
        width: Int,
        height: Int,
        alpha: Bool = false,
        to url: URL
    ) throws {
        let image = try makeImage(width: width, height: height, alpha: alpha)
        try write(image, to: url, type: .png, properties: nil)
    }

    static func writeJPEG(
        width: Int,
        height: Int,
        exifDateTimeOriginal: String? = nil,
        to url: URL
    ) throws {
        let image = try makeImage(width: width, height: height, alpha: false)

        var properties: [CFString: Any] = [:]
        if let exifDateTimeOriginal {
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifDateTimeOriginal: exifDateTimeOriginal
            ] as CFDictionary
        }
        try write(image, to: url, type: .jpeg, properties: properties as CFDictionary)
    }

    /// Stands in for an iPhone photo when testing the HEIC preselection.
    static func writeHEIC(
        width: Int,
        height: Int,
        alpha: Bool = false,
        to url: URL
    ) throws {
        let image = try makeImage(width: width, height: height, alpha: alpha)
        try write(image, to: url, type: .heic, properties: nil)
    }

    /// Bytes that are definitely not a decodable image.
    static func writeCorrupt(to url: URL) throws {
        try Data("this is not an image".utf8).write(to: url)
    }

    // MARK: - Reading back

    static func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw TestImageError.unreadable(url.lastPathComponent) }
        return (width, height)
    }

    /// The container's actual type, read from the file — not guessed from the
    /// extension, which is exactly what these tests must not trust.
    static func containerType(of url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source)
        else { throw TestImageError.unreadable(url.lastPathComponent) }
        return type as String
    }

    static func exifDateTimeOriginal(of url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        else { return nil }
        return exif[kCGImagePropertyExifDateTimeOriginal] as? String
    }

    // MARK: - Private

    private static func makeImage(width: Int, height: Int, alpha: Bool) throws -> CGImage {
        let alphaInfo: CGImageAlphaInfo = alpha ? .premultipliedLast : .noneSkipLast
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        ) else { throw TestImageError.contextFailed }

        if !alpha {
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        // An off-centre block gives the encoders real detail to chew on, so
        // quality differences actually show up in file size.
        context.setFillColor(CGColor(red: 1, green: 0.6, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 3, height: height / 2))

        guard let image = context.makeImage() else { throw TestImageError.contextFailed }
        return image
    }

    private static func write(
        _ image: CGImage,
        to url: URL,
        type: UTType,
        properties: CFDictionary?
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else { throw TestImageError.destinationFailed }

        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.destinationFailed
        }
    }

    enum TestImageError: Error {
        case contextFailed
        case destinationFailed
        case unreadable(String)
    }
}
