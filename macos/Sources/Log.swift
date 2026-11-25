import Foundation

/// Лог пишется и в stderr, и в файл: приложение можно запустить как из терминала,
/// так и через `open` (тогда stderr никуда не виден, а файл остаётся).
final class Log {
    static let shared = Log()

    static let fileURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/keydeck.log")

    private let handle: FileHandle?
    private let queue = DispatchQueue(label: "keydeck.log")

    private init() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Log.fileURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if !fm.fileExists(atPath: Log.fileURL.path) {
            fm.createFile(atPath: Log.fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: Log.fileURL)
        handle?.seekToEndOfFile()
    }

    func write(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        queue.sync {
            if let handle, let data = line.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
    }
}
