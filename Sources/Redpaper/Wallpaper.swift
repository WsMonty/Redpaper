import AppKit
import ImageIO

/// A wallpaper that was shown: what's on each screen, and the history list.
struct Applied: Codable, Hashable {
    let id: String
    let file: String
    let title: String
    let permalink: String
    let subreddit: String
    var date = Date()
}

extension NSScreen {
    var key: String {
        "\((deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)"
    }
    var pixelSize: CGSize {
        CGSize(width: frame.width * backingScaleFactor, height: frame.height * backingScaleFactor)
    }
}

enum Wallpaper {
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Redpaper", isDirectory: true)

    /// Unique filename per post: macOS caches wallpapers by path.
    static func download(_ post: Post) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(post.id).\(post.imageURL.pathExtension.lowercased())")
        if fm.fileExists(atPath: file.path) { return file }

        var req = URLRequest(url: post.imageURL)
        req.setValue(Reddit.userAgent, forHTTPHeaderField: "User-Agent")
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        let http = resp as? HTTPURLResponse
        guard http?.statusCode == 200, http?.mimeType?.hasPrefix("image/") == true else {
            try? fm.removeItem(at: tmp)
            throw AppError("Image download failed (\(http?.statusCode ?? 0)).")
        }
        try fm.moveItem(at: tmp, to: file)
        return file
    }

    /// Reads the pixel size from the first 128 KB of the image (headers sit at the start).
    static func probeSize(_ url: URL) async -> CGSize? {
        var req = URLRequest(url: url)
        req.setValue("bytes=0-131071", forHTTPHeaderField: "Range")
        req.setValue(Reddit.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Fill the screen, cropping whatever doesn't fit.
    static func set(_ file: URL, on screen: NSScreen) throws {
        try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
        ])
    }

    /// Copies a wallpaper to ~/Pictures/Redpaper, named after its post title, and returns the copy.
    static func saveToPictures(_ item: Applied) throws -> URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Redpaper", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: item.file)
        let name = String(item.title.replacingOccurrences(of: "[/:]", with: "-", options: .regularExpression).prefix(120))
        // Title clash: add the post id. If that exists too, this image was already saved.
        for candidate in [name, "\(name) (\(item.id))"] {
            let target = dir.appendingPathComponent(candidate).appendingPathExtension(source.pathExtension)
            if fm.fileExists(atPath: target.path) { continue }
            try fm.copyItem(at: source, to: target)
            return target
        }
        return dir.appendingPathComponent("\(name) (\(item.id))").appendingPathExtension(source.pathExtension)
    }

    /// Deletes every downloaded image that's neither on screen nor in the history.
    static func cleanUp(keeping inUse: Set<String>) {
        let fm = FileManager.default
        for file in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where !inUse.contains(file.path) {
            try? fm.removeItem(at: file)
        }
    }

    /// Small, cached preview for the popup (full images can be 8K).
    @MainActor static func thumbnail(_ path: String) async -> NSImage? {
        if let hit = thumbnails.object(forKey: path as NSString) { return hit }
        let image = await Task.detached { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceThumbnailMaxPixelSize: 640,
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: .zero)
        }.value
        if let image { thumbnails.setObject(image, forKey: path as NSString) }
        return image
    }

    @MainActor private static let thumbnails = NSCache<NSString, NSImage>()
}
