import XCTest
@testable import Symplast

final class SessionDraftTests: XCTestCase {
    func testBuildIgnoresIncludeNodeModules() {
        XCTAssertTrue(NewSessionDraft.buildIgnores.contains("node_modules/"))
    }

    func testBuildIgnoreCheckboxBlocksNodeModules() {
        var draft = NewSessionDraft()
        draft.ignoreBuildArtifacts = true
        XCTAssertTrue(draft.effectiveIgnores.contains("node_modules/"))
        draft.ignoreBuildArtifacts = false
        XCTAssertFalse(draft.effectiveIgnores.contains("node_modules/"))
    }

    func testBuildIgnoreStateRoundTripsThroughSavedSession() {
        var draft = NewSessionDraft()
        draft.name = "project-sync"
        draft.localPath = "/Users/test/project"
        draft.sshHost = "host.example"
        draft.sshPath = "/srv/project"
        draft.ignoreBuildArtifacts = true

        let definition = draft.toSavedSession()
        XCTAssertTrue(definition.ignorePaths.contains("node_modules/"))

        let restored = NewSessionDraft(from: definition)
        XCTAssertTrue(restored.ignoreBuildArtifacts)
        XCTAssertFalse(restored.ignoreText.contains("node_modules/"),
                       "node_modules/ belongs to the checkbox, not the free-form list")
    }

    func testDefinitionFromBeforeNodeModulesStillRestoresBuildCheckbox() {
        let definition = SavedSession(name: "project-sync",
                                      alpha: "/Users/test/project",
                                      beta: "host.example:/srv/project",
                                      mode: "two-way-safe",
                                      ignorePaths: ["target/"],
                                      ignoreVCS: false)
        let restored = NewSessionDraft(from: definition)
        XCTAssertTrue(restored.ignoreBuildArtifacts)
        XCTAssertTrue(restored.toSavedSession().ignorePaths.contains("node_modules/"))
    }

    // MARK: - Sync modes

    func testOneWayModesMapToMutagenModesViaSafeCheckbox() {
        typealias Mode = NewSessionDraft.ModeChoice
        XCTAssertEqual(Mode.oneWayLocalToRemote.mutagenMode(oneWaySafe: true), "one-way-safe")
        XCTAssertEqual(Mode.oneWayLocalToRemote.mutagenMode(oneWaySafe: false), "one-way-replica")
        XCTAssertEqual(Mode.oneWayRemoteToLocal.mutagenMode(oneWaySafe: true), "one-way-safe")
        XCTAssertEqual(Mode.oneWayRemoteToLocal.mutagenMode(oneWaySafe: false), "one-way-replica")
        XCTAssertEqual(Mode.twoWaySafe.mutagenMode(oneWaySafe: false), "two-way-safe")
    }

    func testOneWayDirectionIsExpressedByEndpointOrder() {
        var draft = remoteDraft()
        draft.modeChoice = .oneWayLocalToRemote
        var saved = draft.toSavedSession()
        XCTAssertEqual(saved.alpha, "/Users/test/project")
        XCTAssertEqual(saved.beta, "admin@host.example:/srv/project")
        XCTAssertEqual(saved.mode, "one-way-safe")

        draft.modeChoice = .oneWayRemoteToLocal
        draft.oneWaySafe = false
        saved = draft.toSavedSession()
        XCTAssertEqual(saved.alpha, "admin@host.example:/srv/project")
        XCTAssertEqual(saved.beta, "/Users/test/project")
        XCTAssertEqual(saved.mode, "one-way-replica")
    }

    func testOneWayDirectionAndSafeFlagRoundTripWhenEditing() {
        var draft = remoteDraft()
        draft.modeChoice = .oneWayRemoteToLocal
        draft.oneWaySafe = false

        let restored = NewSessionDraft(from: draft.toSavedSession())
        XCTAssertEqual(restored.modeChoice, .oneWayRemoteToLocal)
        XCTAssertFalse(restored.oneWaySafe)
        XCTAssertEqual(restored.localPath, "/Users/test/project")
        XCTAssertEqual(restored.sshHost, "host.example")

        draft.modeChoice = .oneWayLocalToRemote
        draft.oneWaySafe = true
        let safe = NewSessionDraft(from: draft.toSavedSession())
        XCTAssertEqual(safe.modeChoice, .oneWayLocalToRemote)
        XCTAssertTrue(safe.oneWaySafe)
    }

    func testOneWayDetailTextFollowsSafeCheckbox() {
        typealias Mode = NewSessionDraft.ModeChoice
        for mode in [Mode.oneWayLocalToRemote, Mode.oneWayRemoteToLocal] {
            let safe = mode.detail(oneWaySafe: true)
            let replica = mode.detail(oneWaySafe: false)
            XCTAssertNotEqual(safe, replica)
            XCTAssertTrue(safe.contains("left untouched"), safe)
            XCTAssertTrue(replica.contains("deleted"), replica)
        }
    }

    private func remoteDraft() -> NewSessionDraft {
        var draft = NewSessionDraft()
        draft.name = "project-sync"
        draft.localPath = "/Users/test/project"
        draft.sshHost = "host.example"
        draft.sshPath = "/srv/project"
        return draft
    }
}
