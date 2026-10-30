import Foundation

/// Subsequence matching with bonuses for the things people actually type:
/// prefixes ("saf" → Safari), word initials ("vsc" → Visual Studio Code),
/// and runs of consecutive characters.
public enum FuzzyMatcher {
    public struct Match: Equatable {
        public let score: Double
        /// Indices into the candidate (as an array of Characters) that matched the query.
        public let positions: [Int]
    }

    public static func match(_ query: String, in candidate: String) -> Match? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return nil }
        let original = Array(candidate)
        let c = Array(candidate.lowercased())
        guard q.count <= c.count else { return nil }

        let wordStarts = (0..<original.count).map { isWordStart(at: $0, in: original) }

        // Two candidate alignments: one that jumps to word starts when it can
        // (good for acronyms), and the plain leftmost greedy one (good for prefixes
        // and substrings). Keep whichever scores higher.
        var best: Match?
        for preferWordStarts in [true, false] {
            guard let positions = align(q, in: c, wordStarts: wordStarts, preferWordStarts: preferWordStarts) else { continue }
            let match = Match(score: score(positions: positions, query: q, candidate: c, wordStarts: wordStarts), positions: positions)
            if best == nil || match.score > best!.score { best = match }
        }
        return best
    }

    private static func align(_ q: [Character], in c: [Character], wordStarts: [Bool], preferWordStarts: Bool) -> [Int]? {
        var positions: [Int] = []
        var start = 0
        for ch in q {
            var found: Int?
            if preferWordStarts {
                found = (start..<c.count).first { wordStarts[$0] && c[$0] == ch }
            }
            if found == nil {
                found = (start..<c.count).first { c[$0] == ch }
            }
            guard let index = found else { return nil }
            positions.append(index)
            start = index + 1
        }
        return positions
    }

    private static func score(positions: [Int], query q: [Character], candidate c: [Character], wordStarts: [Bool]) -> Double {
        var score = 0.0
        for (i, pos) in positions.enumerated() {
            score += 1
            if pos == 0 {
                score += 20
            } else if wordStarts[pos] {
                score += 12
            }
            if i > 0 {
                let gap = pos - positions[i - 1] - 1
                if gap == 0 {
                    score += 8
                } else {
                    score -= min(Double(gap), 10) * 0.5
                }
            }
        }
        if c.starts(with: q) { score += 30 }
        if c.count == q.count { score += 20 }
        // Tie-break towards shorter names: "Mail" over "Mail Downloader".
        score -= Double(c.count) * 0.05
        return score
    }

    private static func isWordStart(at index: Int, in chars: [Character]) -> Bool {
        guard index > 0 else { return true }
        let previous = chars[index - 1]
        let current = chars[index]
        if previous.isWhitespace || previous.isPunctuation || previous == "-" || previous == "_" { return true }
        if !previous.isLetter && current.isLetter { return true }      // "1Password" → P
        if previous.isLowercase && current.isUppercase { return true } // camelCase
        return false
    }
}
