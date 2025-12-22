import Foundation
import Carbon
import os.log

@MainActor
final class InputSourceManager {
    static let shared = InputSourceManager()
    
    private let logger = Logger.inputSource
    
    /// Maps macOS layout IDs to our layout IDs
    private let macOSToLayoutID: [String: String] = [
        // Russian
        "com.apple.keylayout.Russian": "ru_pc",
        "com.apple.keylayout.RussianWin": "ru_pc",
        "com.apple.keylayout.Russian-Phonetic": "ru_phonetic_yasherty",
        // Hebrew
        "com.apple.keylayout.Hebrew": "he_standard",
        "com.apple.keylayout.Hebrew-QWERTY": "he_qwerty",
        "com.apple.keylayout.Hebrew-PC": "he_pc",
        // English
        "com.apple.keylayout.US": "en_us",
        "com.apple.keylayout.ABC": "en_us",
    ]
    
    private init() {
        logger.info("InputSourceManager initialized")
    }
    
    /// Detects all installed keyboard layouts and returns our layout IDs
    func detectInstalledLayouts() -> [String: String] {
        var result: [String: String] = [
            "en": "en_us",
            "ru": "ru_pc", 
            "he": "he_standard"
        ]
        
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any
        ]
        
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            logger.warning("Failed to get input source list")
            return result
        }
        
        for i in 0..<CFArrayGetCount(list) {
            guard let src = CFArrayGetValueAtIndex(list, i) else { continue }
            let source = unsafeBitCast(src, to: TISInputSource.self)
            
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let macOSID = unsafeBitCast(idPtr, to: CFString.self) as String
            
            if let ourID = macOSToLayoutID[macOSID] {
                // Determine language from our ID
                if ourID.hasPrefix("ru") {
                    result["ru"] = ourID
                    logger.info("Detected Russian layout: \(ourID)")
                } else if ourID.hasPrefix("he") {
                    result["he"] = ourID
                    logger.info("Detected Hebrew layout: \(ourID)")
                } else if ourID.hasPrefix("en") {
                    result["en"] = ourID
                }
            }
        }
        
        return result
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
