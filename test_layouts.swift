#!/usr/bin/env swift
import Foundation
import Carbon

// Load layouts.json
let jsonPath = "\(FileManager.default.currentDirectoryPath)/OMFK/Sources/Resources/layouts.json"
guard let data = FileManager.default.contents(atPath: jsonPath) else {
    print("Cannot load layouts.json")
    exit(1)
}

struct LayoutInfo: Codable {
    let id: String
    let name: String
    let language: String
    let appleId: String
}

struct KeyMapping: Codable {
    let n: String?
    let s: String?
}

struct LayoutData: Codable {
    let layouts: [LayoutInfo]
    let map: [String: [String: KeyMapping]]
}

let layoutData = try! JSONDecoder().decode(LayoutData.self, from: data)

// Build char->key map
var charToKey: [String: [Character: String]] = [:]
for (keyCode, layoutsMap) in layoutData.map {
    for (layoutID, mapping) in layoutsMap {
        if charToKey[layoutID] == nil { charToKey[layoutID] = [:] }
        if let ch = mapping.n?.first, mapping.n?.count == 1 {
            charToKey[layoutID]![ch] = keyCode
        }
    }
}

// Detect installed layouts
let filter: [CFString: Any] = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any]
guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
    print("Cannot get input sources")
    exit(1)
}

var appleIdToLayout: [String: LayoutInfo] = [:]
for l in layoutData.layouts { appleIdToLayout[l.appleId] = l }

var activeLayouts: [String: String] = [:]
print("Installed layouts:")
for i in 0..<CFArrayGetCount(list) {
    guard let src = CFArrayGetValueAtIndex(list, i) else { continue }
    let source = unsafeBitCast(src, to: TISInputSource.self)
    guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
    let appleId = unsafeBitCast(idPtr, to: CFString.self) as String
    
    if let info = appleIdToLayout[appleId] {
        print("  \(appleId) -> \(info.id) (\(info.language))")
        if activeLayouts[info.language] == nil {
            activeLayouts[info.language] = info.id
        }
    } else {
        print("  \(appleId) -> NOT FOUND IN JSON")
    }
}

print("\nActive layouts for OMFK:")
print("  en: \(activeLayouts["en"] ?? "us")")
print("  ru: \(activeLayouts["ru"] ?? "russianwin")")
print("  he: \(activeLayouts["he"] ?? "hebrew")")

// Test conversion
func convert(_ text: String, from: String, to: String) -> String {
    guard let srcMap = charToKey[from] else { return "NO SRC MAP" }
    var result = ""
    for ch in text {
        if let key = srcMap[ch], let tgtCh = layoutData.map[key]?[to]?.n {
            result += tgtCh
        } else {
            result.append(ch)
        }
    }
    return result
}

let heLayout = activeLayouts["he"] ?? "hebrew"
let ruLayout = activeLayouts["ru"] ?? "russianwin"
let enLayout = activeLayouts["en"] ?? "us"

print("\n=== Testing conversions ===")

// Test: גהבדתנ (привет typed on Hebrew-QWERTY, not Hebrew-PC!)
let test1 = "גהבדתנ"
print("\nInput: \(test1)")
print("  Using detected \(heLayout):")
print("    \(heLayout)->ru: \(convert(test1, from: heLayout, to: ruLayout))")
print("  Using ALL Hebrew variants:")
for heVar in ["hebrew", "hebrew_pc", "hebrew_qwerty"] {
    let result = convert(test1, from: heVar, to: ruLayout)
    print("    \(heVar)->ru: \(result)")
}

// Test: привет
let test2 = "привет"
print("\nInput: \(test2)")
print("  ru->\(heLayout): \(convert(test2, from: ruLayout, to: heLayout))")

// Test: ghbdtn (привет on English)
let test3 = "ghbdtn"
print("\nInput: \(test3)")
print("  en->ru: \(convert(test3, from: enLayout, to: ruLayout))")
