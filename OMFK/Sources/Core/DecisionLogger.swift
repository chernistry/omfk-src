import Foundation

/// Logs language detection decisions to a local file for debugging.
/// Writes to `~/.omfk/debug.log`, overwriting on startup.
final class DecisionLogger: @unchecked Sendable {
    static let shared = DecisionLogger()
    private let logURL: URL?
    private let queue = DispatchQueue(label: "com.omfk.logger")
    
    init() {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let omfkDir = home.appendingPathComponent(".omfk")
        
        var url: URL? = nil
        do {
            try fileManager.createDirectory(at: omfkDir, withIntermediateDirectories: true)
            url = omfkDir.appendingPathComponent("debug.log")
            
            // Overwrite log on startup
            if let validUrl = url {
                try "".write(to: validUrl, atomically: true, encoding: .utf8)
                print("DecisionLogger: Logging to \(validUrl.path)")
            }
        } catch {
            print("DecisionLogger: Failed to setup log file: \(error)")
        }
        self.logURL = url
    }
    
    func log(_ message: String) {
        guard let url = logURL else { return }
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                // Determine if we need to create it (should exist from init, but maybe deleted)
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    func logDecision(token: String, path: String, result: LanguageDecision, scores: [LanguageHypothesis: Double]? = nil) {
        var msg = "Input: '\(token)' | Path: \(path) | Result: \(result.language.rawValue) (Conf: \(String(format: "%.2f", result.confidence)))"
        
        if let scores = scores {
            msg += " | Scores: " + scores.map { "\($0.key): \(String(format: "%.2f", $0.value))" }.joined(separator: ", ")
        }
        
        log(msg)
    }
}
