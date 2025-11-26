import Foundation

struct LayoutMapper {
    // RU ↔ EN mapping (QWERTY/ЙЦУКЕН)
    private static let ruToEn: [Character: Character] = [
        "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p",
        "х": "[", "ъ": "]", "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j", "л": "k",
        "д": "l", "ж": ";", "э": "'", "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m",
        "б": ",", "ю": ".", "ё": "`",
        "Й": "Q", "Ц": "W", "У": "E", "К": "R", "Е": "T", "Н": "Y", "Г": "U", "Ш": "I", "Щ": "O", "З": "P",
        "Х": "{", "Ъ": "}", "Ф": "A", "Ы": "S", "В": "D", "А": "F", "П": "G", "Р": "H", "О": "J", "Л": "K",
        "Д": "L", "Ж": ":", "Э": "\"", "Я": "Z", "Ч": "X", "С": "C", "М": "V", "И": "B", "Т": "N", "Ь": "M",
        "Б": "<", "Ю": ">", "Ё": "~"
    ]
    
    private static let enToRu: [Character: Character] = Dictionary(uniqueKeysWithValues: ruToEn.map { ($1, $0) })
    
    // HE ↔ EN mapping (QWERTY/Hebrew standard)
    private static let heToEn: [Character: Character] = [
        "/": "q", "'": "w", "ק": "e", "ר": "r", "א": "t", "ט": "y", "ו": "u", "ן": "i", "ם": "o", "פ": "p",
        "ש": "a", "ד": "s", "ג": "d", "כ": "f", "ע": "g", "י": "h", "ח": "j", "ל": "k", "ך": "l", "ף": ";",
        "ז": "z", "ס": "x", "ב": "c", "ה": "v", "נ": "b", "מ": "n", "צ": "m", "ת": ",", "ץ": "."
    ]
    
    private static let enToHe: [Character: Character] = Dictionary(uniqueKeysWithValues: heToEn.map { ($1, $0) })
    
    static func convert(_ text: String, from: Language, to: Language) -> String? {
        guard from != to else { return text }
        
        let map: [Character: Character]?
        switch (from, to) {
        case (.russian, .english): map = ruToEn
        case (.english, .russian): map = enToRu
        case (.hebrew, .english): map = heToEn
        case (.english, .hebrew): map = enToHe
        default: return nil
        }
        
        guard let mapping = map else { return nil }
        return String(text.map { mapping[$0] ?? $0 })
    }
}
