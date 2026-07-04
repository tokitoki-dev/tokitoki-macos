//
//  tracklm_macosTests.swift
//  tracklm-macosTests
//
//  Created by Eren on 2026/06/05.
//

import XCTest
@testable import tracklm_macos

final class tracklm_macosTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    func testAgentProcessDoesNotUseEnvironmentOverride() throws {
        let script = try makeFakeAgent()
        setenv("TOKITOKI_AGENT_BIN", script.path, 1)
        setenv("TRACKLM_AGENT_BIN", script.path, 1)
        addTeardownBlock {
            unsetenv("TOKITOKI_AGENT_BIN")
            unsetenv("TRACKLM_AGENT_BIN")
        }

        XCTAssertNotEqual(AgentProcess.resolveBinary(), script)
    }

    func testCopilotExporterFilePathUsesParentForWatchAndFileForSync() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("copilot-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("copilot.jsonl")
        try "{}\n".write(to: file, atomically: true, encoding: .utf8)
        setenv("COPILOT_OTEL_FILE_EXPORTER_PATH", file.path, 1)
        addTeardownBlock {
            unsetenv("COPILOT_OTEL_FILE_EXPORTER_PATH")
            try? FileManager.default.removeItem(at: dir)
        }

        XCTAssertEqual(
            AgentDataDirectories.syncArguments(for: ["copilot"]),
            ["--provider-dir", "copilot=\(file.path)"]
        )
        XCTAssertEqual(AgentDataDirectories.watchPaths(for: ["copilot"]), [dir.path])
    }

    @MainActor
    func testCLIClientGetsAPIKey() async throws {
        let script = try makeFakeAgent()
        let client = try XCTUnwrap(AgentClient(executableURL: script))

        let apiKey = try await client.getAPIKey()

        XCTAssertEqual(apiKey, "tokitoki_test_key")
    }

    @MainActor
    func testCLIClientSetsAPIKey() async throws {
        let script = try makeFakeAgent()
        let client = try XCTUnwrap(AgentClient(executableURL: script))

        try await client.setAPIKey("tokitoki_test_key")
    }

    @MainActor
    func testCLIClientRunsOneSyncOperation() async throws {
        let claudeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        setenv("CLAUDE_CONFIG_DIR", claudeDir.path, 1)
        addTeardownBlock {
            unsetenv("CLAUDE_CONFIG_DIR")
            try? FileManager.default.removeItem(at: claudeDir)
        }

        let script = try makeFakeAgent()
        let client = try XCTUnwrap(AgentClient(executableURL: script))

        try await client.sync(providers: ["claude"])
    }

    private func makeFakeAgent() throws -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokitoki-test-\(UUID().uuidString)")
        let source = """
        #!/bin/sh
        if [ \"$1\" = 'set' ]; then
          test \"$2\" = 'key'
          test \"$3\" = 'tokitoki_test_key'
          printf '%s\\n' '{\"ok\":true}'
          exit 0
        fi
        if [ \"$1\" = 'get' ]; then
          test \"$2\" = 'key'
          printf '%s\\n' 'tokitoki_test_key'
          exit 0
        fi
        test \"$1\" = '--provider-dir'
        case \"$2\" in
          claude=*) path=\"${2#claude=}\" ;;
          *) exit 1 ;;
        esac
        test -d \"$path\"
        printf '%s\\n' '{\"ok\":true}'
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: script) }
        return script
    }

}
