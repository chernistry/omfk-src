import Foundation
import os.log

extension Logger {
    static let app = Logger(subsystem: "com.chernistry.omfk", category: "app")
    static let engine = Logger(subsystem: "com.chernistry.omfk", category: "engine")
    static let detection = Logger(subsystem: "com.chernistry.omfk", category: "detection")
}
