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

    @MainActor
    func testCLIClientDecodesStatusAndDailyUsage() async throws {
        let script = try makeFakeAgent()
        let client = try XCTUnwrap(AgentClient(executableURL: script))

        let status = try await client.status()
        XCTAssertEqual(status.indexedEvents, 42)
        XCTAssertEqual(status.serverURL, "https://tracklm.example")
        XCTAssertTrue(status.hasAPIKey)

        let today = DateFormatter.agentDay.string(from: .now)
        let tokens = try await client.todayTokens()
        XCTAssertEqual(tokens, 30, "The client must sum every project for the current day (\(today)).")
    }

    private func makeFakeAgent() throws -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokitoki-test-\(UUID().uuidString)")
        let today = DateFormatter.agentDay.string(from: .now)
        let source = """
        #!/bin/sh
        case \"$1\" in
          status) printf '%s\\n' '{\"indexed_events\":42,\"server_url\":\"https://tracklm.example\",\"has_api_key\":true}' ;;
          daily) printf '%s\\n' '{\"data\":[{\"date\":\"\(today)\",\"total_tokens\":10},{\"date\":\"\(today)\",\"total_tokens\":20},{\"date\":\"2000-01-01\",\"total_tokens\":999}]}' ;;
          *) printf '%s\\n' '{\"ok\":true,\"events\":0,\"accepted\":0,\"duplicate\":0}' ;;
        esac
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: script) }
        return script
    }

}

private extension DateFormatter {
    static let agentDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}
