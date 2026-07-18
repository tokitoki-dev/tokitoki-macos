import AppKit
import Foundation
import XCTest
@testable import tokitoki_macos

@MainActor
final class APIKeyVerifierTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testValidKeyUsesDedicatedPOSTEndpointAndBearerHeader() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/auth/api-key/verify")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer tokitoki_valid_key"
            )
            return Self.response(for: request, status: 200, body: #"{"valid":true}"#)
        }

        let verifier = makeVerifier()
        let isValid = try await verifier.verify("tokitoki_valid_key")

        XCTAssertTrue(isValid)
    }

    func testInvalidOrRevokedKeyReturnsFalse() async throws {
        StubURLProtocol.handler = { request in
            Self.response(for: request, status: 401, body: #"{"valid":false}"#)
        }

        let verifier = makeVerifier()
        let isValid = try await verifier.verify("tokitoki_revoked_key")

        XCTAssertFalse(isValid)
    }

    func testServiceFailureIsNotReportedAsInvalidKey() async {
        StubURLProtocol.handler = { request in
            Self.response(
                for: request,
                status: 503,
                body: #"{"valid":false,"error":"verification_unavailable"}"#
            )
        }

        let verifier = makeVerifier()

        do {
            _ = try await verifier.verify("tokitoki_unknown_key")
            XCTFail("Expected verification to fail")
        } catch let error as APIKeyVerifier.VerificationError {
            guard case .serviceUnavailable = error else {
                return XCTFail("Unexpected verification error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedSuccessResponseIsRejected() async {
        StubURLProtocol.handler = { request in
            Self.response(for: request, status: 200, body: #"{"ok":true}"#)
        }

        let verifier = makeVerifier()

        do {
            _ = try await verifier.verify("tokitoki_valid_key")
            XCTFail("Expected malformed response to fail")
        } catch let error as APIKeyVerifier.VerificationError {
            guard case .invalidResponse = error else {
                return XCTFail("Unexpected verification error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSettingsPlacesDisabledVerifyButtonBelowEmptyKeyField() throws {
        let controller = SettingsWindowController(
            apiKeyVerifier: APIKeyVerifier(
                serverURL: URL(string: "https://tokitoki.example")!
            )
        )
        let contentView = try XCTUnwrap(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()

        let verifyButton = try XCTUnwrap(
            descendants(of: contentView)
                .compactMap { $0 as? NSButton }
                .first { $0.title == "Verify Key" }
        )
        let apiKeyField = try XCTUnwrap(
            descendants(of: contentView)
                .compactMap { $0 as? NSTextField }
                .first { $0.isEditable }
        )
        let buttonFrame = verifyButton.convert(verifyButton.bounds, to: contentView)
        let fieldFrame = apiKeyField.convert(apiKeyField.bounds, to: contentView)

        XCTAssertLessThan(buttonFrame.maxY, fieldFrame.minY)
        XCTAssertFalse(verifyButton.isEnabled)
        XCTAssertEqual(verifyButton.toolTip, "Check this key with the TokiToki server")
    }

    func testVersionLabelAlignsWithAutomaticUpdatesTitle() throws {
        let controller = SettingsWindowController(
            apiKeyVerifier: APIKeyVerifier(
                serverURL: URL(string: "https://tokitoki.example")!
            )
        )
        let contentView = try XCTUnwrap(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()

        let autoUpdateCheckbox = try XCTUnwrap(
            descendants(of: contentView)
                .compactMap { $0 as? NSButton }
                .first { $0.identifier?.rawValue == "autoUpdateCheckbox" }
        )
        let autoUpdateTitleLabel = try XCTUnwrap(
            descendants(of: contentView)
                .compactMap { $0 as? NSTextField }
                .first { $0.identifier?.rawValue == "autoUpdateTitleLabel" }
        )
        let versionLabel = try XCTUnwrap(
            descendants(of: contentView)
                .compactMap { $0 as? NSTextField }
                .first { $0.identifier?.rawValue == "versionLabel" }
        )
        XCTAssertEqual(autoUpdateCheckbox.accessibilityLabel(), "Automatically check for updates")
        XCTAssertEqual(versionLabel.stringValue, "Version \(AppConfig.version)")
        XCTAssertFalse(versionLabel.stringValue.contains("("))
        let titleFrame = autoUpdateTitleLabel.convert(autoUpdateTitleLabel.bounds, to: contentView)
        let versionFrame = versionLabel.convert(versionLabel.bounds, to: contentView)

        XCTAssertEqual(versionFrame.minX, titleFrame.minX, accuracy: 0.5)
    }

    private func makeVerifier() -> APIKeyVerifier {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIKeyVerifier(
            serverURL: URL(string: "https://tokitoki.example")!,
            session: URLSession(configuration: configuration)
        )
    }

    private static func response(
        for request: URLRequest,
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
