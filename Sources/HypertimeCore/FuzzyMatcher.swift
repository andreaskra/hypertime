import Foundation

public struct FuzzyMatch<T>: Sendable where T: Sendable {
    public let item: T
    public let score: Int
    /// Indices into the *original* string, for highlighting.
    public let matchedIndices: [Int]

    public init(item: T, score: Int, matchedIndices: [Int]) {
        self.item = item
        self.score = score
        self.matchedIndices = matchedIndices
    }
}

/// Ranked subsequence matching for the project dropdown (§5.4).
public enum FuzzyMatcher {

    public static let matchedCharScore = 10
    public static let prefixBonus = 15
    public static let wordBoundaryBonus = 8
    public static let consecutiveBonus = 5
    public static let gapPenalty = -1

    public static func rank<T: Sendable>(
        _ query: String,
        in items: [T],
        key: (T) -> String,
        recency: (T) -> Date?
    ) -> [FuzzyMatch<T>] {
        let foldedQuery = fold(query.trimmingCharacters(in: .whitespacesAndNewlines)).characters

        // Empty query: everything, most recently used first, then name.
        if foldedQuery.isEmpty {
            let ordered = items.enumerated().sorted { a, b in
                orderedByRecency(a.element, b.element, index: (a.offset, b.offset), key: key, recency: recency)
            }
            return ordered.map { FuzzyMatch(item: $0.element, score: 0, matchedIndices: []) }
        }

        var matches: [(match: FuzzyMatch<T>, index: Int)] = []
        for (index, item) in items.enumerated() {
            guard let scored = score(foldedQuery, against: key(item)) else { continue }
            matches.append((FuzzyMatch(item: item, score: scored.score, matchedIndices: scored.indices), index))
        }

        return matches.sorted { a, b in
            if a.match.score != b.match.score { return a.match.score > b.match.score }
            return orderedByRecency(a.match.item, b.match.item, index: (a.index, b.index), key: key, recency: recency)
        }.map(\.match)
    }

    /// Case-insensitive, trimmed exact match — decides "existing project" vs "create new" on commit.
    public static func exactMatch<T>(_ query: String, in items: [T], key: (T) -> String) -> T? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return items.first { key($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle }
    }

    // MARK: - Scoring

    static func score(_ foldedQuery: [Character], against name: String) -> (score: Int, indices: [Int])? {
        let folded = fold(name)
        let haystack = folded.characters
        guard !haystack.isEmpty else { return nil }

        var indices: [Int] = []
        var total = 0
        var haystackIndex = 0
        var previousMatch: Int?

        for needle in foldedQuery {
            var found: Int?
            var cursor = haystackIndex
            while cursor < haystack.count {
                if haystack[cursor] == needle { found = cursor; break }
                cursor += 1
            }
            guard let position = found else { return nil }

            total += matchedCharScore
            if position == 0 { total += prefixBonus }
            if isWordBoundary(haystack, position) { total += wordBoundaryBonus }
            if let previous = previousMatch {
                if position == previous + 1 {
                    total += consecutiveBonus
                } else {
                    total += gapPenalty * (position - previous - 1)
                }
            }
            indices.append(folded.originalIndices[position])
            previousMatch = position
            haystackIndex = position + 1
        }

        return (total, Array(Set(indices)).sorted())
    }

    private static func isWordBoundary(_ haystack: [Character], _ position: Int) -> Bool {
        guard position > 0 else { return true }
        let previous = haystack[position - 1]
        return previous == " " || previous == "-" || previous == "_" || previous == "/" || previous == "." || previous == ":"
    }

    private static func orderedByRecency<T>(
        _ a: T, _ b: T,
        index: (Int, Int),
        key: (T) -> String,
        recency: (T) -> Date?
    ) -> Bool {
        let ra = recency(a), rb = recency(b)
        switch (ra, rb) {
        case let (x?, y?) where x != y: return x > y
        case (nil, _?): return false
        case (_?, nil): return true
        default: break
        }
        let na = key(a).lowercased(), nb = key(b).lowercased()
        if na != nb { return na < nb }
        return index.0 < index.1
    }

    // MARK: - Folding

    struct Folded {
        var characters: [Character]
        /// For each folded character, the index of the character it came from in the original string.
        var originalIndices: [Int]
    }

    static func fold(_ string: String) -> Folded {
        var characters: [Character] = []
        var originalIndices: [Int] = []
        for (offset, character) in string.enumerated() {
            let folded = String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            for f in folded {
                characters.append(f)
                originalIndices.append(offset)
            }
        }
        return Folded(characters: characters, originalIndices: originalIndices)
    }
}
