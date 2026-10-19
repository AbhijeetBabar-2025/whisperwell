import Foundation

public enum LivePreview {
    /// How often the audio so far is re-transcribed while the hotkey is held.
    public static let interval: TimeInterval = 0.8
    /// Only the most recent audio is previewed, so each pass stays fast on long dictations.
    public static let maxSeconds = 20

    /// The end of a live transcript, cut at a word boundary to fit the indicator.
    public static func tail(_ text: String, maxCharacters: Int = 60) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        let end = String(trimmed.suffix(maxCharacters))
        // Drop the partial first word so the preview starts cleanly.
        if let space = end.firstIndex(of: " ") {
            return "…" + end[end.index(after: space)...]
        }
        return "…" + end
    }
}
