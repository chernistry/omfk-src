import Foundation

/// Compact word frequency model loaded from bundled resources.
/// File format: `word<TAB>count` (sorted by descending count).
struct WordFrequencyModel: Sendable {
    private let rankByWord: [String: Int]
    private let maxRank: Int

    static func loadLanguage(_ lang: String) throws -> WordFrequencyModel {
        #if SWIFT_PACKAGE
        guard let url = Bundle.module.url(forResource: "\(lang)_unigrams", withExtension: "tsv", subdirectory: "LanguageModels") else {
            throw LexiconError.resourceNotFound(lang)
        }
        #else
        guard let url = Bundle.main.url(forResource: "\(lang)_unigrams", withExtension: "tsv", subdirectory: "LanguageModels") else {
            throw LexiconError.resourceNotFound(lang)
        }
        #endif

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LexiconError.invalidFormat("Non-UTF8 TSV for \(lang)")
        }

        var out: [String: Int] = [:]
        out.reserveCapacity(200_000)

        var rank = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: true)
            guard let wordRaw = parts.first, !wordRaw.isEmpty else { continue }
            let word = wordRaw.lowercased()
            if out[word] == nil {
                out[word] = rank
                rank += 1
            }
        }

        return WordFrequencyModel(rankByWord: out, maxRank: max(1, rank - 1))
    }

    /// Score in [0, 1]. Unknown words score 0.
    func score(_ word: String) -> Double {
        let key = word.lowercased()
        guard let rank = rankByWord[key] else { return 0.0 }
        return 1.0 - (Double(rank) / Double(maxRank))
    }

    func contains(_ word: String) -> Bool {
        rankByWord[word.lowercased()] != nil
    }
}

enum LexiconError: Error {
    case resourceNotFound(String)
    case invalidFormat(String)
}
