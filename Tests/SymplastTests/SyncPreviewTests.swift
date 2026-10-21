import XCTest
@testable import Symplast

final class SyncPreviewTests: XCTestCase {
    private func file(_ path: String, size: Int64 = 10, modified: Int64 = 1_000) -> PreviewFile {
        PreviewFile(path: path, size: size, modified: modified)
    }

    // MARK: - Classification

    func testOneWayLocalToRemoteSafeLeavesTargetOnlyFilesAlone() {
        let entries = SyncPreview.classify(
            local: [file("new.txt"), file("same.txt"), file("newer.txt", modified: 2_000),
                    file("older.txt", modified: 500)],
            remote: [file("target-only.txt"), file("same.txt"),
                     file("newer.txt", modified: 1_000), file("older.txt", modified: 1_000)],
            oneWaySource: .local, replica: false)

        XCTAssertEqual(outcome(of: "new.txt", in: entries), .created(.target))
        XCTAssertEqual(outcome(of: "target-only.txt", in: entries), .kept(.target))
        XCTAssertEqual(outcome(of: "same.txt", in: entries), .unchanged)
        XCTAssertEqual(outcome(of: "newer.txt", in: entries), .overwritten(.target))
        XCTAssertEqual(outcome(of: "older.txt", in: entries), .kept(.target),
                       "a newer target file is left alone in safe mode")
    }

    func testOneWayReplicaDeletesAndOverwritesTheTarget() {
        let entries = SyncPreview.classify(
            local: [file("newer.txt", modified: 2_000), file("older.txt", modified: 500)],
            remote: [file("target-only.txt"), file("newer.txt", modified: 1_000),
                     file("older.txt", modified: 1_000)],
            oneWaySource: .local, replica: true)

        XCTAssertEqual(outcome(of: "target-only.txt", in: entries), .deleted(.target))
        XCTAssertEqual(outcome(of: "newer.txt", in: entries), .overwritten(.target))
        XCTAssertEqual(outcome(of: "older.txt", in: entries), .overwritten(.target),
                       "replica overwrites even when the target is newer")
    }

    func testOneWayRemoteToLocalTouchesTheLocalFolder() {
        let entries = SyncPreview.classify(
            local: [file("local-only.txt"), file("stale.txt", modified: 500)],
            remote: [file("remote-only.txt"), file("stale.txt", modified: 2_000)],
            oneWaySource: .target, replica: false)

        XCTAssertEqual(outcome(of: "local-only.txt", in: entries), .kept(.local))
        XCTAssertEqual(outcome(of: "remote-only.txt", in: entries), .created(.local))
        XCTAssertEqual(outcome(of: "stale.txt", in: entries), .overwritten(.local))

        let replica = SyncPreview.classify(
            local: [file("local-only.txt")], remote: [],
            oneWaySource: .target, replica: true)
        XCTAssertEqual(outcome(of: "local-only.txt", in: replica), .deleted(.local))
    }

    func testTwoWayPropagatesBothWaysAndFlagsTiesAsConflicts() {
        let entries = SyncPreview.classify(
            local: [file("local-only.txt"), file("local-newer.txt", modified: 2_000),
                    file("remote-newer.txt", modified: 1_000), file("tied.txt", size: 10, modified: 1_000)],
            remote: [file("remote-only.txt"), file("local-newer.txt", modified: 1_000),
                     file("remote-newer.txt", modified: 2_000), file("tied.txt", size: 20, modified: 1_000)],
            oneWaySource: nil, replica: false)

        XCTAssertEqual(outcome(of: "local-only.txt", in: entries), .created(.target))
        XCTAssertEqual(outcome(of: "remote-only.txt", in: entries), .created(.local))
        XCTAssertEqual(outcome(of: "local-newer.txt", in: entries), .overwritten(.target))
        XCTAssertEqual(outcome(of: "remote-newer.txt", in: entries), .overwritten(.local))
        XCTAssertEqual(outcome(of: "tied.txt", in: entries), .conflict,
                       "same timestamp but different content has no clear winner")
    }

    // MARK: - Ignore patterns

    func testIgnoreMatcherCoversNamesFoldersAndWildcards() {
        let matcher = IgnoreMatcher(patterns: ["node_modules/", "*.o", "build/out/", "/config/*.json"])

        XCTAssertTrue(matcher.ignores("node_modules/left-pad/index.js"))
        XCTAssertTrue(matcher.ignores("packages/app/node_modules/x.js"))
        XCTAssertFalse(matcher.ignores("src/node_modulesx.txt"))
        XCTAssertFalse(matcher.ignores("node_modules"),
                       "a file named like an ignored folder is not covered by the folder rule")

        XCTAssertTrue(matcher.ignores("src/main.o"))
        XCTAssertFalse(matcher.ignores("src/main.c"))

        XCTAssertTrue(matcher.ignores("build/out/report.xml"))
        XCTAssertFalse(matcher.ignores("build/report.xml"))

        XCTAssertTrue(matcher.ignores("config/app.json"))
        XCTAssertFalse(matcher.ignores("other/config/app.json"),
                       "a leading slash anchors the pattern to the root")
    }

    func testIgnoreMatcherPrunesIgnoredDirectories() {
        let matcher = IgnoreMatcher(patterns: ["node_modules/", "build/out/"])
        XCTAssertTrue(matcher.ignoresDirectory("node_modules"))
        XCTAssertTrue(matcher.ignoresDirectory("packages/app/node_modules"))
        XCTAssertTrue(matcher.ignoresDirectory("build/out"))
        XCTAssertFalse(matcher.ignoresDirectory("build"))
        XCTAssertFalse(matcher.ignoresDirectory("src"))
    }

    // MARK: - Remote inventory parsing

    func testRemoteInventoryParsesGNUAndBSDStatOutput() {
        let files = RemoteInventory.parse("""
        docs/readme.md\t120\t1697040000.123456789
        ./src/main.c\t5\t1697040001
        broken-line-without-tabs
        """)
        XCTAssertEqual(files, [
            PreviewFile(path: "docs/readme.md", size: 120, modified: 1_697_040_000),
            PreviewFile(path: "src/main.c", size: 5, modified: 1_697_040_001)
        ])
    }

    // MARK: - Local scan and full report

    func testLocalInventoryScansSizesAndSkipsIgnoredTrees() throws {
        let root = try makeDirectory { root in
            try write("readme.md", in: root, contents: "hello")
            try write("src/main.c", in: root, contents: "int main(){}")
            try write("node_modules/huge/index.js", in: root, contents: "ignored")
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let (files, truncated) = SyncPreviewService.localInventory(
            at: root.path, ignores: IgnoreMatcher(patterns: ["node_modules/"]))
        XCTAssertFalse(truncated)
        XCTAssertEqual(files.map(\.path).sorted(), ["readme.md", "src/main.c"])
        XCTAssertEqual(files.first { $0.path == "readme.md" }?.size, 5)
    }

    func testReportClassifiesTwoLocalFoldersWithTheDraftMode() async throws {
        let source = try makeDirectory { root in
            try write("kept.txt", in: root, contents: "same", modified: Date(timeIntervalSince1970: 1_000_000))
            try write("changed.txt", in: root, contents: "newer", modified: Date(timeIntervalSince1970: 2_000_000))
            try write("new.txt", in: root, contents: "fresh", modified: Date(timeIntervalSince1970: 2_000_000))
        }
        let target = try makeDirectory { root in
            try write("kept.txt", in: root, contents: "same", modified: Date(timeIntervalSince1970: 1_000_000))
            try write("changed.txt", in: root, contents: "old", modified: Date(timeIntervalSince1970: 1_000_000))
            try write("target-only.txt", in: root, contents: "gone", modified: Date(timeIntervalSince1970: 1_000_000))
        }
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: target)
        }

        var draft = NewSessionDraft()
        draft.name = "preview-test"
        draft.localPath = source.path
        draft.targetKind = .local
        draft.localTargetPath = target.path
        draft.modeChoice = .oneWayLocalToRemote
        draft.oneWaySafe = false

        let report = await SyncPreviewService.report(for: draft)
        XCTAssertNil(report.notice)
        XCTAssertEqual(report.unchangedCount, 1)
        XCTAssertEqual(Set(report.entries.map(\.outcome)),
                       [.created(.target), .overwritten(.target), .deleted(.target)],
                       "replica mode: new file created, changed file overwritten, target-only file deleted")
        XCTAssertEqual(outcome(of: "changed.txt", in: report.entries), .overwritten(.target))
        XCTAssertEqual(outcome(of: "target-only.txt", in: report.entries), .deleted(.target))
    }

    func testReportExplainsWhenTheTargetCannotBeCompared() async {
        var draft = NewSessionDraft()
        draft.localPath = NSHomeDirectory()
        draft.targetKind = .custom
        draft.customTarget = "docker://container/srv/app"

        let report = await SyncPreviewService.report(for: draft)
        XCTAssertNotNil(report.notice)
        XCTAssertTrue(report.notice?.contains("Preview isn’t available") == true, report.notice ?? "")
        XCTAssertTrue(report.entries.isEmpty)
    }

    /// Ignore patterns apply to both sides of a sync, but the SSH inventory
    /// lists everything — an ignored `.git/` on the remote must not show up as
    /// "added locally".
    func testIgnoredPathsAreExcludedFromBothSidesOfThePreview() async throws {
        let source = try makeDirectory { root in
            try write("readme.md", in: root, contents: "same",
                      modified: Date(timeIntervalSince1970: 1_000_000))
        }
        defer { try? FileManager.default.removeItem(at: source) }

        let fixture = try makeFakeSSH { """
        printf '%s\\t%s\\t%s\\n' 'readme.md' '4' '1000000'
        printf '%s\\t%s\\t%s\\n' '.git/config' '395' '1000000'
        """ }
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        var draft = NewSessionDraft()
        draft.name = "preview-test"
        draft.localPath = source.path
        draft.targetKind = .remote
        draft.sshHost = "host.example"
        draft.sshPath = "/srv/app"

        let report = await SyncPreviewService.report(for: draft, sshExecutable: fixture.script)
        XCTAssertNil(report.notice)
        XCTAssertEqual(report.unchangedCount, 1, "readme.md is identical on both sides")
        XCTAssertTrue(report.entries.isEmpty,
                      "the ignored .git/config must not appear: \(report.entries)")
    }

    // MARK: - Fixtures

    private func makeFakeSSH(_ body: () -> String) throws -> (directory: URL, script: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode/symplast-preview-ssh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("ssh")
        try "#!/bin/sh\n\(body())\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (directory, script)
    }

    private func makeDirectory(_ populate: (URL) throws -> Void) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode/symplast-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try populate(directory)
        return directory
    }

    private func write(_ relativePath: String, in root: URL, contents: String,
                       modified: Date? = nil) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }

    private func outcome(of path: String, in entries: [SyncPreview.Entry]) -> PreviewOutcome? {
        entries.first { $0.path == path }?.outcome
    }
}
