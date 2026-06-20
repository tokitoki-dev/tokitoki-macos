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
    func testCLIClientRunsOneSyncOperation() async throws {
        let script = try makeFakeAgent()
        let client = try XCTUnwrap(AgentClient(executableURL: script))

        try await client.sync(apiKey: "tokitoki_test_key", providers: ["claude"])
    }

    private func makeFakeAgent() throws -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokitoki-test-\(UUID().uuidString)")
        let source = """
        #!/bin/sh
        test \"$1\" = '--api-key-stdin'
        test \"$2\" = '--providers'
        test \"$3\" = 'claude'
        read key
        test \"$key\" = 'tokitoki_test_key'
        printf '%s\\n' '{\"ok\":true}'
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: script) }
        return script
    }

}
