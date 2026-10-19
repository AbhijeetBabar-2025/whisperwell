import Foundation

/// Short dictations ("Sounds good.", "On my way.") rarely need an AI rewrite, and skipping it
/// makes them paste in well under a second instead of waiting for the cleanup model.
public enum ShortPhrase {
    /// Words that mean the speaker wants something fixed, so cleanup should still run.
    static let cues: Set<String> = ["um", "uh", "erm", "er", "hmm", "mm", "ah", "actually", "scratch", "wait", "mean"]

    /// True when the transcript is short enough to paste as-is.
    public static func canSkipCleanup(_ transcript: String, maxWords: Int) -> Bool {
        guard maxWords > 0 else { return false }
        let words = transcript
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= maxWords else { return false }
        return words.allSatisfy { !cues.contains($0) }
    }

    /// Fits a phrase to the text before the cursor, like cleanup would: mid-sentence it starts lowercase.
    public static func fitted(_ phrase: String, textBefore: String) -> String {
        guard let last = textBefore.trimmingCharacters(in: .whitespaces).last,
              !".!?:\n".contains(last),
              let first = phrase.first, first.isUppercase else { return phrase }
        // Keep "I" and acronyms like "PDF" as they are.
        let firstWord = phrase.prefix { !$0.isWhitespace }.trimmingCharacters(in: .punctuationCharacters)
        if firstWord == "I" || firstWord.hasPrefix("I'") || (firstWord.count > 1 && firstWord == firstWord.uppercased()) {
            return phrase
        }
        return first.lowercased() + phrase.dropFirst()
    }
}
