import Foundation
import Testing
@testable import HypertimeCore

fileprivate struct Item: Sendable {
    let name: String
    let used: Date?
    init(_ name: String, _ used: Date? = nil) { self.name = name; self.used = used }
}

private func rank(_ query: String, _ items: [Item]) -> [String] {
    FuzzyMatcher.rank(query, in: items, key: \.name, recency: \.used).map(\.item.name)
}

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {
    fileprivate let items = [
        Item("Hypertime", Date(timeIntervalSince1970: 300)),
        Item("Hyper Space", Date(timeIntervalSince1970: 200)),
        Item("Admin", Date(timeIntervalSince1970: 100)),
        Item("Client · Müller", nil),
        Item("time tracking", Date(timeIntervalSince1970: 50)),
    ]

    @Test("empty query returns everything by recency then name")
    func empty() {
        #expect(rank("", items) == ["Hypertime", "Hyper Space", "Admin", "time tracking", "Client · Müller"])
        #expect(rank("   ", items).count == items.count)
    }

    @Test("subsequence matching filters out non-matches")
    func filtering() {
        #expect(rank("hyp", items) == ["Hypertime", "Hyper Space"])
        #expect(rank("zzz", items).isEmpty)
        #expect(rank("hs", items) == ["Hyper Space"])            // across a word boundary
    }

    @Test("prefix beats a later match")
    func prefixWins() {
        let result = rank("time", items)
        #expect(result.first == "time tracking")
        #expect(result.contains("Hypertime"))
    }

    @Test("diacritic and case insensitive")
    func folding() {
        #expect(rank("muller", items) == ["Client · Müller"])
        #expect(rank("MÜLLER", items) == ["Client · Müller"])
        #expect(rank("ADMIN", items) == ["Admin"])
    }

    @Test("matched indices point at the original string")
    func indices() {
        let match = FuzzyMatcher.rank("mul", in: items, key: \.name, recency: \.used).first
        let name = Array("Client · Müller")
        #expect(match?.matchedIndices.map { name[$0] } == ["M", "ü", "l"])
    }

    @Test("ties break by recency then name")
    func ties() {
        let a = Item("alpha", Date(timeIntervalSince1970: 10))
        let b = Item("alpha", Date(timeIntervalSince1970: 20))
        #expect(rank("alpha", [a, b]) == ["alpha", "alpha"])
        let older = Item("aa", Date(timeIntervalSince1970: 1))
        let newer = Item("ab", Date(timeIntervalSince1970: 900))
        #expect(rank("a", [older, newer]).first == "ab")
    }

    @Test("consecutive characters score higher than scattered ones")
    func consecutive() {
        let dense = Item("abc")
        let sparse = Item("axbxc")
        #expect(rank("abc", [sparse, dense]) == ["abc", "axbxc"])
    }

    @Test("exactMatch is case-insensitive and trimmed")
    func exact() {
        #expect(FuzzyMatcher.exactMatch("  hypertime ", in: items, key: \.name)?.name == "Hypertime")
        #expect(FuzzyMatcher.exactMatch("hyper", in: items, key: \.name) == nil)
        #expect(FuzzyMatcher.exactMatch("", in: items, key: \.name) == nil)
    }
}
