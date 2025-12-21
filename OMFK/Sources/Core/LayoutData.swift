//
//  LayoutData.swift
//  OMFK
//
//  Created by O.M.F.K Gen on 2025-12-21.
//

import Foundation

/// Top-level container for the layouts.json data.
struct LayoutData: Codable {
    let schemaVersion: String
    let generatedAt: String
    let modifiers: ModifierInfo
    let layouts: [String: LayoutInfo]
    let layoutAliases: [String: String]
    let keys: [KeyInfo]
    let deadKeyCombos: [DeadKeyCombo]
    let ambiguities: [AmbiguityInfo]
    let map: [String: [String: KeyMapping]]
    
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case modifiers
        case layouts
        case layoutAliases = "layout_aliases"
        case keys
        case deadKeyCombos = "dead_key_combos"
        case ambiguities
        case map
    }
}

struct ModifierInfo: Codable {
    let n: String
    let s: String
    let a: String
    let sa: String
    let implicitNull: [String]
    
    enum CodingKeys: String, CodingKey {
        case n, s, a, sa
        case implicitNull = "implicit_null"
    }
}

struct LayoutInfo: Codable {
    let name: String
    let platform: String
    let source: String?
    let note: String?
}

struct KeyInfo: Codable {
    let code: String
    let qwertyLabel: String
    
    enum CodingKeys: String, CodingKey {
        case code
        case qwertyLabel = "qwerty_label"
    }
}

struct DeadKeyCombo: Codable {
    let layout: String
    let key: String
    let modifier: String
    let deadKey: String
    
    enum CodingKeys: String, CodingKey {
        case layout, key, modifier
        case deadKey = "dead_key"
    }
}

struct AmbiguityInfo: Codable {
    let layout: String
    let key: String
    let modifier: String
    let reason: String
    let out: String
}

struct KeyMapping: Codable {
    let n: String?
    let s: String?
    let a: String?
    let sa: String?
}
