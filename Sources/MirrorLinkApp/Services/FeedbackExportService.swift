import Foundation

enum FeedbackExportService {
    static func export(report: FeedbackReport, attachments: [URL], destination: URL,
                       cancellation: ProcessCancellation? = nil) throws -> URL {
        try export(preview: report.preview, attachments: attachments, destination: destination, cancellation: cancellation)
    }

    /// The caller captures the displayed preview before dispatching to a worker,
    /// so a language change cannot replace the text the user just reviewed.
    static func export(preview: String, attachments: [URL], destination: URL,
                       cancellation: ProcessCancellation? = nil) throws -> URL {
        guard attachments.count <= 8 else { throw DeviceToolsError.invalidAttachment }
        guard destination.isFileURL, destination.pathExtension.lowercased() == "zip",
              !FileManager.default.fileExists(atPath: destination.path) else { throw DeviceToolsError.saveFailed }
        try ToolFileSafety.prepareDirectory(destination.deletingLastPathComponent())
        let staging = try ToolFileSafety.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }
        let content = staging.appendingPathComponent("MirrorLink-feedback", isDirectory: true)
        try ToolFileSafety.prepareDirectory(content)
        try ToolFileSafety.writeExclusive(Data(preview.utf8), to: content.appendingPathComponent("diagnostics.txt"))
        var total: Int64 = 0
        let allowed = Set(["png", "jpg", "jpeg", "heic", "mov", "mp4", "mkv"])
        for (index, source) in attachments.enumerated() {
            guard allowed.contains(source.pathExtension.lowercased()) else { throw DeviceToolsError.invalidAttachment }
            let file = content.appendingPathComponent("attachment-\(index + 1)" + ToolFileSafety.safeExtension(source))
            do { try ToolFileSafety.copyRegularFile(source, to: file, cancellation: cancellation, maximumBytes: 536_870_912) }
            catch DeviceToolsError.invalidFile { throw DeviceToolsError.invalidAttachment }
            let size = (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            total += Int64(size)
            guard total <= 1_073_741_824, try hasMediaHeader(file) else { throw DeviceToolsError.invalidAttachment }
        }
        let archive = staging.appendingPathComponent("feedback.zip")
        let result = BoundedProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", content.path, archive.path],
            timeout: 120, outputLimit: 65_536, cancellation: cancellation)
        if cancellation?.isCancelled == true { throw DeviceToolsError.cancelled }
        if result.timedOut { throw DeviceToolsError.timedOut }
        guard result.succeeded else { throw DeviceToolsError.saveFailed }
        // moveItem fails if another file appeared at the selected destination.
        do { try FileManager.default.moveItem(at: archive, to: destination) }
        catch { throw DeviceToolsError.saveFailed }
        return destination
    }

    private static func hasMediaHeader(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 16) ?? Data()
        if bytes.starts(with: [137,80,78,71,13,10,26,10]) { return true }
        if bytes.starts(with: [255,216,255]) { return true }
        if bytes.starts(with: [26,69,223,163]) { return true }
        guard bytes.count >= 8 else { return false }
        let atom = String(decoding: bytes[4..<8], as: UTF8.self)
        return ["ftyp", "moov", "mdat", "wide", "free"].contains(atom)
    }
}
