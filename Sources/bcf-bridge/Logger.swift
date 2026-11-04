import Foundation

/// Schrijft naar het scherm en naar een logbestand in ~/Library/Logs/BCF Bridge.
final class Logger {
    let start = Date()
    let fileURL: URL
    private var handle: FileHandle?

    init() {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/BCF Bridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        fileURL = folder.appendingPathComponent("bcf-bridge-\(f.string(from: Date())).log")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
    }

    func line(_ text: String) {
        let t = String(format: "%9.3f", Date().timeIntervalSince(start))
        write("[\(t)] \(text)")
    }

    func plain(_ text: String) { write(text) }

    private func write(_ s: String) {
        print(s)
        fflush(stdout)
        if let d = (s + "\n").data(using: .utf8) { handle?.write(d) }
    }
}
