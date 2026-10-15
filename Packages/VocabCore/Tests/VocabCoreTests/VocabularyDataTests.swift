import XCTest
@testable import VocabCore

/// Integrity checks for the bundled `vocabulary.json` dataset.
final class VocabularyDataTests: XCTestCase {
    private static var cached: [VocabEntry]?

    private func entries() throws -> [VocabEntry] {
        if let cached = Self.cached { return cached }
        let loaded = try VocabularyRepository.loadBundled()
        Self.cached = loaded
        return loaded
    }

    func testHasAtLeast700Entries() throws {
        XCTAssertGreaterThanOrEqual(try entries().count, 700)
    }

    func testEveryCategoryHasAtLeast90Entries() throws {
        let counts = Dictionary(grouping: try entries(), by: \.category).mapValues(\.count)
        for category in Category.allCases {
            XCTAssertGreaterThanOrEqual(counts[category] ?? 0, 90, "category \(category.rawValue)")
        }
    }

    func testEveryCategoryDifficultyPairHasAtLeast20Entries() throws {
        let all = try entries()
        for category in Category.allCases {
            for difficulty in Difficulty.allCases {
                let n = all.filter { $0.category == category && $0.difficulty == difficulty }.count
                XCTAssertGreaterThanOrEqual(n, 20, "\(category.rawValue)/\(difficulty.rawValue)")
            }
        }
    }

    func testAllLanguagesPresentAndNonEmpty() throws {
        for entry in try entries() {
            for language in Language.allCases {
                let term = entry.terms[language]?.trimmingCharacters(in: .whitespaces) ?? ""
                let definition = entry.definitions[language]?.trimmingCharacters(in: .whitespaces) ?? ""
                let example = entry.examples?[language]?.trimmingCharacters(in: .whitespaces) ?? ""
                XCTAssertFalse(term.isEmpty, "\(entry.id) missing term [\(language.rawValue)]")
                XCTAssertFalse(definition.isEmpty, "\(entry.id) missing definition [\(language.rawValue)]")
                XCTAssertFalse(example.isEmpty, "\(entry.id) missing example [\(language.rawValue)]")
            }
        }
    }

    func testIdsAreUniqueAndWellFormed() throws {
        let all = try entries()
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "duplicate ids")
        for entry in all {
            XCTAssertTrue(entry.id.hasPrefix(entry.category.rawValue + "-"), "\(entry.id) prefix")
            let suffix = entry.id.dropFirst(entry.category.rawValue.count + 1)
            XCTAssertTrue(suffix.count == 4 && suffix.allSatisfy(\.isNumber), "\(entry.id) index")
        }
    }

    func testEnglishTermsAreUnique() throws {
        var seen: [String: String] = [:]
        for entry in try entries() {
            let key = entry.term(in: .english).lowercased()
            if let other = seen[key] {
                XCTFail("duplicate English term '\(key)': \(other), \(entry.id)")
            }
            seen[key] = entry.id
        }
    }

    func testDefinitionsFitInWidget() throws {
        for entry in try entries() {
            for (language, definition) in entry.definitions {
                XCTAssertLessThanOrEqual(definition.count, 120, "\(entry.id) [\(language.rawValue)] too long")
            }
        }
    }
}
