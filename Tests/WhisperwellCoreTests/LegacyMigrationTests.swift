import XCTest
@testable import WhisperwellCore

final class LegacyMigrationTests: XCTestCase {
    private var root: URL!
    private var home: URL { root.appendingPathComponent("home") }
    private var appSupport: URL { root.appendingPathComponent("support") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    func testMovesOldConfigAndModels() throws {
        try write("{\"old\":true}", to: home.appendingPathComponent(".config/flowlite/config.json"))
        try write("weights", to: appSupport.appendingPathComponent("FlowLite/Models/m.bin"))

        try LegacyMigration.run(home: home, appSupport: appSupport)

        XCTAssertEqual(try read(home.appendingPathComponent(".config/whisperwell/config.json")), "{\"old\":true}")
        XCTAssertEqual(try read(appSupport.appendingPathComponent("Whisperwell/Models/m.bin")), "weights")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".config/flowlite/config.json").path))
    }

    func testKeepsExistingNewFiles() throws {
        try write("old", to: home.appendingPathComponent(".config/flowlite/config.json"))
        try write("new", to: home.appendingPathComponent(".config/whisperwell/config.json"))

        try LegacyMigration.run(home: home, appSupport: appSupport)

        XCTAssertEqual(try read(home.appendingPathComponent(".config/whisperwell/config.json")), "new")
        XCTAssertEqual(try read(home.appendingPathComponent(".config/flowlite/config.json")), "old")
    }

    func testNothingToMigrate() throws {
        XCTAssertNoThrow(try LegacyMigration.run(home: home, appSupport: appSupport))
    }
}
