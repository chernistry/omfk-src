import Foundation
import Carbon
import os.log

@MainActor
final class InputSourceManager {
    static let shared = InputSourceManager()
    
    private let logger = Logger(subsystem: "com.chernistry.omfk", category: "InputSource")
    
    private init() {}
    
    func currentLanguage() -> Language? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        
        guard let langsPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return nil
        }
        
        let langsUnmanaged = unsafeBitCast(langsPointer, to: CFArray.self)
        let langs = langsUnmanaged as [AnyObject]
        guard let tag = langs.first as? String else { return nil }
        
        logger.debug("Current input source languages: \(tag, privacy: .public)")
        
        if tag.hasPrefix("ru") { return .russian }
        if tag.hasPrefix("he") { return .hebrew }
        if tag.hasPrefix("en") { return .english }
        return nil
    }
    
    func switchTo(language: Language) {
        let langCode = language.rawValue
        logger.info("Switching input source to \(langCode, privacy: .public)")
        
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any
        ]
        
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            logger.error("Failed to copy input source list")
            return
        }
        
        let count = CFArrayGetCount(list)
        
        for index in 0..<count {
            guard let src = CFArrayGetValueAtIndex(list, index) else { continue }
            let source = unsafeBitCast(src, to: TISInputSource.self)
            guard let langsPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
                continue
            }
            let langsUnmanaged = unsafeBitCast(langsPointer, to: CFArray.self)
            let langsCount = CFArrayGetCount(langsUnmanaged)
            var tags: [String] = []
            for i in 0..<langsCount {
                if let langPtr = CFArrayGetValueAtIndex(langsUnmanaged, i) {
                    let str = unsafeBitCast(langPtr, to: CFString.self) as String
                    tags.append(str)
                }
            }
            if tags.contains(where: { $0.hasPrefix(langCode) }) {
                let status = TISSelectInputSource(source)
                if status == noErr {
                    logger.info("Input source switched to \(langCode, privacy: .public)")
                } else {
                    logger.error("Failed to select input source for \(langCode, privacy: .public), status: \(status)")
                }
                return
            }
        }
        
        logger.error("No input source found for language \(langCode, privacy: .public)")
    }
}
