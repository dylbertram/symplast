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
}
