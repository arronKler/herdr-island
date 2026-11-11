import AppKit
import Darwin
import ImageIO
import UniformTypeIdentifiers

/// Images outlive a terminal attachment: an agent may read the pasted path
/// after the user has returned to the task list.
enum TerminalPasteboard {
    static let imageLimit = 16 * 1_024 * 1_024
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    static func text(from pasteboard: NSPasteboard, directory: URL = imageDirectory) throws -> String? {
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            return files.map { quote($0.path) }.joined(separator: " ")
        }
        if let bytes = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            let path = try stageImage(bytes, directory: directory)
            return quote(path.path)
        }
        return pasteboard.string(forType: .string)
    }

    static var imageDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HerdrIsland/TerminalImages", isDirectory: true)
    }

    static func quote(_ path: String) -> String {
        if !path.contains("'") { return "'" + path + "'" }
        // Claude recognizes a single quoted path, but not concatenated shell
        // quote fragments. Double quotes retain apostrophes without fragments.
        var escaped = path
        for character in ["\\", "\"", "$", "`"] {
            escaped = escaped.replacingOccurrences(of: character, with: "\\" + character)
        }
        return "\"" + escaped + "\""
    }

    static func stageImage(_ bytes: Data, directory: URL) throws -> URL {
        guard !bytes.isEmpty, bytes.count <= imageLimit,
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 40_000_000,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure("图片无法读取或过大（最多 16 MB、4000 万像素）。")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure("无法转换剪贴板图片。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= imageLimit else {
            throw Failure("转换后的图片超过 16 MB，请缩小后再粘贴。")
        }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure("图片缓存目录无效。") }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        cleanup(in: directory)
        let url = directory.appendingPathComponent("paste-\(UUID().uuidString).png")
        // create-new plus restrictive permissions prevents accidental overwrite.
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure("无法保存剪贴板图片。") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do { try file.write(contentsOf: output as Data); try file.close() }
        catch { try? manager.removeItem(at: url); throw error }
        return url
    }

    /// Called when opening a terminal and staging another image. Expired files
    /// are removed on the next use, rather than by a persistent background task.
    static func cleanup(in directory: URL = imageDirectory) {
        let manager = FileManager.default
        guard let values = try? directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return }
        // Only this application's expired, regular PNGs are eligible for cleanup.
        for url in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey])) ?? [] {
            guard url.lastPathComponent.hasPrefix("paste-"), url.pathExtension == "png",
                  let metadata = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey]),
                  metadata.isRegularFile == true, metadata.isSymbolicLink != true,
                  let created = metadata.creationDate, Date().timeIntervalSince(created) > lifetime else { continue }
            try? manager.removeItem(at: url)
        }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
