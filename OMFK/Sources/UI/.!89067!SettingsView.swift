import SwiftUI

// Version is read from VERSION file at build time via build script
// For debug builds, fallback to reading file directly
let appVersion: String = {
    // Try reading from VERSION file (works in debug)
    let possiblePaths = [
        Bundle.main.bundlePath + "/../../../VERSION",  // .build/debug/OMFK -> project root
        Bundle.main.bundlePath + "/../../VERSION",     // OMFK.app/Contents/MacOS -> project root (dev)
    ]
    for path in possiblePaths {
        if let version = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
            return version
        }
    }
    // Fallback: embedded at build time by release script
