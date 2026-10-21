import XCTest
@testable import Symplast

final class RemoteBrowserTests: XCTestCase {
    // MARK: - Listing parsing

    func testParseJoinsFolderNamesOntoTheListedPath() {
        let listing = RemoteListing.parse("""
        /home/deploy
        .
        ./apps
        ./www
        """)
        XCTAssertEqual(listing?.path, "/home/deploy")
        XCTAssertEqual(listing?.directories, ["/home/deploy/apps", "/home/deploy/www"])
        XCTAssertEqual(listing?.names, ["apps", "www"])
    }

    func testParseSortsFoldersAndIgnoresUnexpectedLines() {
        let listing = RemoteListing.parse("""
        /srv
        ./zeta
        ./Alpha
        ./nested/too-deep
        not-a-find-line
        """)
        XCTAssertEqual(listing?.directories, ["/srv/Alpha", "/srv/zeta"])
    }

    func testParseHandlesRootAndEmptyListings() {
        XCTAssertEqual(RemoteListing.parse("/\n.\n./apps\n")?.directories, ["/apps"])
        XCTAssertEqual(RemoteListing.parse("/srv\n.\n")?.directories, [])
        XCTAssertNil(RemoteListing.parse(""))
        XCTAssertNil(RemoteListing.parse("\n\n"))
    }

    // MARK: - Remote script safety

    func testListScriptQuotesPathsInsteadOfInterpolatingThem() {
        let script = RemoteListing.listScript(for: "/srv/it's here; rm -rf /")
        XCTAssertTrue(script.contains("'/srv/it'\\''s here; rm -rf /'"),
                      "the path must appear once, fully quoted: \(script)")
        XCTAssertFalse(script.contains("p=/srv/it's here; rm -rf /"),
                       "an unquoted path would execute as shell: \(script)")
        XCTAssertEqual(RemoteListing.shellQuote("plain"), "'plain'")
    }

    func testListScriptResolvesTildeAndEmptyPathsOnTheRemote() {
        let script = RemoteListing.listScript(for: "")
        XCTAssertTrue(script.contains("\"~\") p=\"$HOME\""))
        XCTAssertTrue(script.contains("[ -n \"$p\" ] || p=\"$HOME\""))
    }

    func testDestinationFormatting() {
        XCTAssertEqual(SSHRemoteClient(user: "deploy", host: "studio.example.com").destination,
                       "deploy@studio.example.com")
        XCTAssertEqual(SSHRemoteClient(user: "  ", host: "studio.example.com").destination,
                       "studio.example.com")
    }

    // MARK: - End-to-end over a fake ssh executable

    func testListParsesTheSSHOutput() async throws {
        let fixture = try makeSSH { """
        printf '%s\\n' '/home/deploy' '.' './apps' './www'
        """ }
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let client = SSHRemoteClient(executableURL: fixture.script,
                                     user: "deploy", host: "studio.example.com")
        let listing = try await client.list(at: "")
        XCTAssertEqual(listing.path, "/home/deploy")
        XCTAssertEqual(listing.directories, ["/home/deploy/apps", "/home/deploy/www"])

        let commands = try String(contentsOf: fixture.directory.appendingPathComponent("commands"))
        XCTAssertTrue(commands.contains("BatchMode=yes"), "browsing must never prompt")
        XCTAssertTrue(commands.contains("deploy@studio.example.com"))
    }

    func testListReportsAMissingFolderAsInaccessible() async throws {
        let fixture = try makeSSH { """
        printf 'symplast: cannot access %s\\n' '/srv/missing' >&2
        exit 2
        """ }
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let client = SSHRemoteClient(executableURL: fixture.script,
                                     user: "deploy", host: "studio.example.com")
        do {
            _ = try await client.list(at: "/srv/missing")
            XCTFail("expected a failure")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("/srv/missing"), message)
        }
    }

    func testListSummarisesAuthenticationFailures() async throws {
        let fixture = try makeSSH { """
        printf '%s\\n' 'deploy@studio.example.com: Permission denied (publickey).' >&2
        exit 255
        """ }
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let client = SSHRemoteClient(executableURL: fixture.script,
                                     user: "deploy", host: "studio.example.com")
        do {
            _ = try await client.list(at: "")
            XCTFail("expected a failure")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("authentication failed"), message)
        }
    }

    func testListTimesOutInsteadOfHanging() async throws {
        let fixture = try makeSSH { """
        sleep 5
        """ }
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let client = SSHRemoteClient(executableURL: fixture.script,
                                     user: "deploy", host: "studio.example.com",
                                     timeout: 0.5)
        do {
            _ = try await client.list(at: "")
            XCTFail("expected a timeout")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("Timed out"), message)
        }
    }

    // MARK: - Fixtures

    private func makeSSH(_ body: () -> String) throws -> (directory: URL, script: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode/symplast-ssh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("ssh")
        try "#!/bin/sh\ndirectory=\"$(dirname \"$0\")\"\necho \"$*\" >> \"$directory/commands\"\n\(body())\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (directory, script)
    }
}
