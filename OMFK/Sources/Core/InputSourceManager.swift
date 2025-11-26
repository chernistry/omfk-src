import Foundation
import Carbon
import os.log

@MainActor
final class InputSourceManager {
    static let shared = InputSourceManager()
    
    private let logger = Logger.inputSource
    
    private init() {
        logger.info("InputSourceManager initialized")
    }
    
    func currentLanguage() -> Language? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            logger.warning("Failed to get current input source")
            return nil
        }
        
        guard let langsPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            logger.warning("Failed to get input source languages property")
            return nil
        }
        
        let langsUnmanaged = unsafeBitCast(langsPointer, to: CFArray.self)
        let langs = langsUnmanaged as [AnyObject]
        guard let tag = langs.first as? String else {
            logger.warning("Failed to extract language tag")
            return nil
        }
        
        logger.info("Current input source language tag: \(tag, privacy: .public)")
        
        if tag.hasPrefix("ru") {
            logger.info("Current layout: Russian")
            return .russian
        }
        if tag.hasPrefix("he") {
            logger.info("Current layout: Hebrew")
            return .hebrew
        }
        if tag.hasPrefix("en") {
            logger.info("Current layout: English")
            return .english
        }
        
        logger.warning("Unrecognized language tag: \(tag, privacy: .public)")
        return nil
    }
    
    func switchTo(language: Language) {
        let langCode = language.rawValue
        logger.info("🔄 === SWITCHING INPUT SOURCE ===")
        logger.info("Target language: \(langCode, privacy: .public)")
        
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any
        ]
        
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            logger.error("❌ Failed to get input source list")
            return
        }
        
        let count = CFArrayGetCount(list)
        logger.info("Found \(count) input sources")
        
        var availableSources: [String] = []
        
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
            
            let tagsStr = tags.joined(separator: ", ")
            availableSources.append(tagsStr)
            logger.debug("Source \(index): [\(tagsStr, privacy: .public)]")
            
            if tags.contains(where: { $0.hasPrefix(langCode) }) {
                logger.info("✅ Found matching source: [\(tagsStr, privacy: .public)]")
                let status = TISSelectInputSource(source)
                if status == noErr {
                    logger.info("✅ Successfully switched to \(langCode, privacy: .public)")
                } else {
                    logger.error("❌ Failed to select input source for \(langCode, privacy: .public), OSStatus: \(status)")
                }
                return
            }
        }
        
        logger.error("❌ No input source found for language: \(langCode, privacy: .public)")
        logger.error("Available sources: \(availableSources.joined(separator: " | "), privacy: .public)")
    }
}
