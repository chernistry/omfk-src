import Foundation

// Version: prefer Info.plist (release), fallback to VERSION file (debug)
let appVersion: String = {
    // 1) Info.plist (works in release .app bundle)
    if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, v != "1.0" {
        return v
    }

    // 2) VERSION file (works in debug builds)
    let possiblePaths = [
        Bundle.main.bundlePath + "/../../../VERSION", // .build/debug/OMFK -> project root
        Bundle.main.bundlePath + "/../../VERSION",
    ]
    for path in possiblePaths {
        if let version = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
            return version
        }
    }

    // 3) Fallback (updated by build script)
    return "1.3"
}()

