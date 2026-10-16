import Foundation

/// Client-side profanity filter for leaderboard nicknames (en, tr, fr, es).
///
/// The term list lives in `Resources/blocked-nicknames.txt` (see the header of that file for its syntax).
/// Nicknames and terms go through the same normalization:
/// lower-casing, diacritics stripped (ş→s, ı→i, é→e, ñ→n…), leetspeak mapped (0→o, 1→i, 3→e, 4→a, 5→s,
/// 7→t, @→a, $→s) and everything that is not a letter treated as a separator.
///
/// A nickname is blocked when
/// - one of its words (or a run of single letters such as "f u c k", or the whole nickname with separators
///   removed) equals a term, also after squeezing repeated letters ("fuuuck"), or
/// - the nickname with separators removed contains a term of 5+ letters (or a term marked `*`).
/// Short terms are whole-word only so that "Cassandra", "Scunthorpe" or "Matthias" stay allowed.
public enum NicknameModeration {
    /// Terms of at least this many letters are also matched inside words.
    public static let substringMinimumLength = 5

    struct TermList: Sendable {
        /// Matched against whole words.
        var wholeWord: Set<String> = []
        /// Matched anywhere in the nickname with separators removed.
        var substring: Set<String> = []

        /// Subsets without doubled letters: only these are compared with fully squeezed text, so that
        /// "fuuuck" is caught without "niger" (squeezed "nigger") blocking "Niger".
        var wholeWordUndoubled: Set<String> = []
        var substringUndoubled: Set<String> = []
    }

    static let terms: TermList = {
        guard let url = Bundle.module.url(forResource: "blocked-nicknames", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("blocked-nicknames.txt missing from VocabCore resources")
            return TermList()
        }
        return parse(text)
    }()

    // MARK: Public API

    /// Whether `nickname` may be shown on the leaderboard.
    public static func isAllowed(_ nickname: String) -> Bool {
        isAllowed(nickname, terms: terms)
    }

    // MARK: Matching

    static func isAllowed(_ nickname: String, terms: TermList) -> Bool {
        let words = self.words(in: nickname)
        guard !words.isEmpty else { return true }
        let collapsed = words.joined()

        // (a) whole words, plus the entire nickname with separators removed ("f.u.c.k", "a s s").
        for candidate in words + [collapsed] {
            if terms.wholeWord.contains(candidate)
                || terms.wholeWord.contains(limitingRuns(candidate))
                || terms.wholeWordUndoubled.contains(squeezed(candidate)) {
                return false
            }
        }
        // (b) long terms anywhere in the collapsed form.
        let limited = limitingRuns(collapsed)
        let squeezedCollapsed = squeezed(collapsed)
        if terms.substring.contains(where: { collapsed.contains($0) || limited.contains($0) }) { return false }
        if terms.substringUndoubled.contains(where: { squeezedCollapsed.contains($0) }) { return false }
        return true
    }

    // MARK: Normalization

    private static let leet: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s",
    ]

    /// Lower-cased, diacritic-free, leet-mapped string; every non-letter becomes a space.
    static func normalize(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        // Ligatures and letters that folding keeps.
        for (from, to) in [("ß", "ss"), ("æ", "ae"), ("œ", "oe"), ("ø", "o"), ("đ", "d"), ("ł", "l")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return String(s.map { ch -> Character in
            if let mapped = leet[ch] { return mapped }
            return ch.isLetter ? ch : " "
        })
    }

    /// Normalized words; runs of single letters are merged ("f u c k" → "fuck").
    static func words(in raw: String) -> [String] {
        let parts = normalize(raw).split(separator: " ").map(String.init)
        var result: [String] = []
        var singles = ""
        for part in parts {
            if part.count == 1 {
                singles += part
                continue
            }
            if !singles.isEmpty { result.append(singles); singles = "" }
            result.append(part)
        }
        if !singles.isEmpty { result.append(singles) }
        return result
    }

    /// Runs of three or more identical letters shortened to two ("assss" → "ass").
    static func limitingRuns(_ s: String) -> String {
        var out = ""
        var last: Character?
        var run = 0
        for ch in s {
            run = ch == last ? run + 1 : 1
            last = ch
            if run <= 2 { out.append(ch) }
        }
        return out
    }

    /// Repeated letters squeezed to one ("fuuuck" → "fuck").
    static func squeezed(_ s: String) -> String {
        var out = ""
        var last: Character?
        for ch in s where ch != last {
            out.append(ch)
            last = ch
        }
        return out
    }

    // MARK: Parsing

    static func parse(_ text: String) -> TermList {
        var list = TermList()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            var wholeWordOnly = false
            var forceSubstring = false
            if line.hasPrefix("=") { wholeWordOnly = true; line.removeFirst() }
            if line.hasSuffix("*") { forceSubstring = true; line.removeLast() }
            let term = words(in: line).joined()
            guard !term.isEmpty else { continue }

            let undoubled = squeezed(term) == term
            list.wholeWord.insert(term)
            if undoubled { list.wholeWordUndoubled.insert(term) }
            if forceSubstring || (!wholeWordOnly && term.count >= substringMinimumLength) {
                list.substring.insert(term)
                if undoubled { list.substringUndoubled.insert(term) }
            }
        }
        return list
    }
}
