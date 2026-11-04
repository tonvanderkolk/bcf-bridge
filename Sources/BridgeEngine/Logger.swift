import Foundation

/// Schrijft naar een logbestand in ~/Library/Logs/BCF Bridge, optioneel naar het scherm,
/// en geeft elke regel door aan `onLine` (voor het logvenster van de app).
public final class Logger {
    public let start = Date()
    public let fileURL: URL
    public static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/BCF Bridge", isDirectory: true)
    }

    /// Ook naar stdout schrijven (command line)
    public var echo = true
    public var onLine: ((String) -> Void)?

    private var handle: FileHandle?
    private var bytesWritten = 0
    private let maxBytes = 50_000_000

    public init() {
        let folder = Self.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Self.removeOldLogs(in: folder)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        fileURL = folder.appendingPathComponent("bcf-bridge-\(f.string(from: Date())).log")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
    }

    /// Logbestanden ouder dan 14 dagen opruimen
    static func removeOldLogs(in folder: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let limit = Date().addingTimeInterval(-14 * 24 * 3600)
        for f in files where f.pathExtension == "log" {
            if let d = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d < limit {
                try? fm.removeItem(at: f)
            }
        }
    }

    public func line(_ text: String) {
        let t = String(format: "%9.3f", Date().timeIntervalSince(start))
        write("[\(t)] \(text)")
    }

    public func plain(_ text: String) { write(text) }

    private func write(_ s: String) {
        if echo {
            print(s)
            fflush(stdout)
        }
        onLine?(s)
        // Bij een heel lang draaiende app het bestand niet onbeperkt laten groeien
        guard bytesWritten < maxBytes, let d = (s + "\n").data(using: .utf8) else { return }
        handle?.write(d)
        bytesWritten += d.count
        if bytesWritten >= maxBytes {
            handle?.write("[log file full, further lines only in the log window]\n".data(using: .utf8)!)
        }
    }
}
