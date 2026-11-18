import Foundation
import Darwin

enum ToolFileSafety {
    static let maximumFileSize: Int64 = 2_147_483_648

    static func prepareDirectory(_ directory: URL) throws {
        guard directory.isFileURL else { throw DeviceToolsError.invalidFile }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw DeviceToolsError.invalidFile }
    }

    /// Exclusive creation prevents replacing an existing file or following a symlink.
    static func writeExclusive(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw DeviceToolsError.saveFailed }
        var completed = false
        defer { close(fd); if !completed { try? FileManager.default.removeItem(at: url) } }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw DeviceToolsError.saveFailed }
                offset += written
            }
        }
        completed = true
    }

    /// Copies bytes from one regular file descriptor; symbolic links and folders
    /// are never traversed. A size cap also applies if the source grows while read.
    static func copyRegularFile(_ source: URL, to destination: URL,
                                cancellation: ProcessCancellation?, maximumBytes: Int64 = maximumFileSize) throws {
        guard source.isFileURL else { throw DeviceToolsError.invalidFile }
        let sourceFD = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard sourceFD >= 0 else { throw DeviceToolsError.invalidFile }
        defer { close(sourceFD) }
        var info = stat()
        guard fstat(sourceFD, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else { throw DeviceToolsError.invalidFile }
        let destinationFD = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard destinationFD >= 0 else { throw DeviceToolsError.saveFailed }
        var complete = false
        defer { close(destinationFD); if !complete { try? FileManager.default.removeItem(at: destination) } }
        var buffer = [UInt8](repeating: 0, count: 262_144), total: Int64 = 0
        while true {
            if cancellation?.isCancelled == true { throw DeviceToolsError.cancelled }
            let count = Darwin.read(sourceFD, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw DeviceToolsError.invalidFile }
            if count == 0 { break }
            total += Int64(count)
            guard total <= maximumBytes else { throw DeviceToolsError.invalidFile }
            try buffer.withUnsafeBytes { bytes in
                var offset = 0
                while offset < count {
                    let written = Darwin.write(destinationFD, bytes.baseAddress!.advanced(by: offset), count - offset)
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { throw DeviceToolsError.saveFailed }
                    offset += written
                }
            }
        }
        complete = true
    }

    static func temporaryDirectory(in parent: URL = FileManager.default.temporaryDirectory) throws -> URL {
        try prepareDirectory(parent)
        let directory = parent.appendingPathComponent("MirrorLink-tools-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return directory
    }

    static func safeExtension(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return !ext.isEmpty && ext.count <= 12 && ext.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }) ? "." + ext : ""
    }
}
