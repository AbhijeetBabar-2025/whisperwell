import Foundation

/// Moves settings and downloaded models from the app's former name, FlowLite, to Whisperwell's
/// locations. Runs at launch; does nothing once moved, or when a Whisperwell file already exists.
public enum LegacyMigration {
    public struct Failure: Error, CustomStringConvertible {
        public let messages: [String]
        public var description: String {
            "Couldn't move old FlowLite files: " + messages.joined(separator: "; ")
                + ". Move them by hand, or delete them to start fresh."
        }
    }

    public static func run(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        appSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) throws {
        let moves = [
            (home.appendingPathComponent(".config/flowlite/config.json"),
             home.appendingPathComponent(".config/whisperwell/config.json")),
            (appSupport.appendingPathComponent("FlowLite/Models", isDirectory: true),
             appSupport.appendingPathComponent("Whisperwell/Models", isDirectory: true)),
        ]
        let fm = FileManager.default
        var failures: [String] = []
        for (old, new) in moves where fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: new.path) {
            do {
                try fm.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: old, to: new)
            } catch {
                failures.append("\(old.path) → \(new.path): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { throw Failure(messages: failures) }
    }
}
