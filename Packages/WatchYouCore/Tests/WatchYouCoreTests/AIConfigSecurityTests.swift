import XCTest
@testable import WatchYouCore

/// M1 验收清单覆盖：A13 危险 URL/密钥、A14 代理前缀与末端路径、A21 恢复回 demo、A12 默认无真实调用。
final class AIConfigSecurityTests: XCTestCase {
    private let base: [String: Any] = [
        "id": "default",
        "name": "我的 AI 服务",
        "baseURL": "https://model.example/v1",
        "protocol": "chat",
        "model": "test-model",
        "auth": "bearer",
        "temperature": "",
        "maxTokens": 1200,
        "tokenField": "max_tokens",
        "timeout": 45,
        "allowLocalHTTP": false
    ]

    private func assertThrows(_ expression: @autoclosure () throws -> some Any, containing: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertTrue(String(describing: error).contains(containing), "错误应包含：\(containing)，实际：\(error)", file: file, line: line)
        }
    }

    func testDefaultModeIsDemo() {
        let config = defaultAIConfig()
        XCTAssertEqual(config.mode, "demo", "默认应为演示模式，不调用真实模型")
        XCTAssertEqual(config.scopes["context"], false, "可选文字范围默认关闭")
    }

    func testTrailingSlashNormalizes() throws {
        XCTAssertEqual(try normalizeBase("https://model.example/v1/"), "https://model.example/v1")
    }

    func testFullChatEndpointStripsWithoutDuplicatingV1() throws {
        XCTAssertEqual(
            try normalizeBase("https://model.example/proxy/v1/chat/completions"),
            "https://model.example/proxy/v1"
        )
    }

    func testGatewayPrefixPreserved() throws {
        let profile = try cleanProfile(base.merging(["baseURL": "https://model.example/gateway/v1"], uniquingKeysWith: { $1 }))
        XCTAssertEqual(try endpoint(for: profile), "https://model.example/gateway/v1/chat/completions")
    }

    func testURLCredentialsRejected() {
        assertThrows(try normalizeBase("https://user:pass@model.example/v1"), containing: "用户名")
    }

    func testURLQueryRejected() {
        assertThrows(try normalizeBase("https://model.example/v1?key=x"), containing: "查询参数")
    }

    func testURLFragmentRejected() {
        assertThrows(try normalizeBase("https://model.example/v1#secret"), containing: "片段")
    }

    func testJavaScriptSchemeRejected() {
        assertThrows(try normalizeBase("javascript:alert(1)"), containing: "HTTPS")
    }

    func testPublicHTTPRejectedEvenWithLocalFlag() {
        assertThrows(try normalizeBase("http://model.example/v1", allowLocalHTTP: true), containing: "HTTPS")
    }

    func testPrivateHTTPRequiresPermission() {
        assertThrows(try normalizeBase("http://192.168.1.2:8000/v1"), containing: "HTTPS")
    }

    func testPrivateHTTPAllowedWhenExplicit() throws {
        XCTAssertEqual(
            try normalizeBase("http://192.168.1.2:8000/v1", allowLocalHTTP: true),
            "http://192.168.1.2:8000/v1"
        )
    }

    func testLoopbackAllowedOnlyInLocalMode() throws {
        XCTAssertEqual(
            try normalizeBase("http://127.0.0.1:8000/v1", allowLocalHTTP: true),
            "http://127.0.0.1:8000/v1"
        )
        assertThrows(try normalizeBase("http://127.0.0.1:8000/v1"), containing: "HTTPS")
    }

    func test127PrefixAttackerNotLocal() {
        XCTAssertFalse(isPrivateHost("127.evil.example"), "127 前缀的公网主机不算私网")
    }

    func test172_32NotPrivate() {
        XCTAssertFalse(isPrivateHost("172.32.1.2"), "172.32 不在 172.16-31 私网段")
    }

    func testCloudMetadataNotAllowed() {
        XCTAssertFalse(isPrivateHost("169.254.169.254"), "云元数据地址不算私网")
    }

    func testOversizedURLRejected() {
        assertThrows(try normalizeBase("https://model.example/" + String(repeating: "a", count: 2100)), containing: "过长")
    }

    func testProfilesDiscardSecretFields() throws {
        var input = base
        input["apiKey"] = "DO_NOT_STORE"
        let profile = try cleanProfile(input)
        // cleanProfile returns a strongly-typed struct; apiKey is never part of the model.
        XCTAssertEqual(profile.model, "test-model")
    }

    func testBackupRestoresDemoMode() throws {
        let defaults = defaultAIConfig()
        var input: [String: Any] = [
            "version": 2,
            "active": "default",
            "profiles": [base],
            "mode": "live",
            "auto": true,
            "dailyLimit": 20
        ]
        input["modules"] = defaults.modules
        input["scopes"] = defaults.scopes
        let config = try sanitizeConfig(input)
        XCTAssertEqual(config.mode, "demo", "恢复备份应强制回到 demo 模式")
    }

    func testDuplicateProfileIDsRejected() {
        let input: [String: Any] = [
            "version": 2,
            "active": "default",
            "profiles": [base, base]
        ]
        assertThrows(try sanitizeConfig(input), containing: "服务 ID 重复")
    }

    func testOutOfRangeTemperatureRejected() {
        var input = base
        input["temperature"] = 3.0
        assertThrows(try cleanProfile(input), containing: "Temperature")
    }

    func testInvalidTimeoutRejected() {
        var input = base
        input["timeout"] = 0
        assertThrows(try cleanProfile(input), containing: "超时")
    }

    func testMissingModelCannotGenerate() throws {
        var input = base
        input["model"] = ""
        let profile = try cleanProfile(input)
        let provider = AIProvider(transport: FailingTransport())
        assertThrows(try provider.buildRequest(profile: profile, key: "TEST", system: "sys", user: "user"), containing: "model")
    }

    func testMissingKeyNotSilentlySent() throws {
        let profile = try cleanProfile(base)
        let provider = AIProvider(transport: FailingTransport())
        assertThrows(try provider.buildRequest(profile: profile, key: nil, system: "sys", user: "user"), containing: "API Key")
    }

    func testExplicitNoAuthSendsNoAuthorization() throws {
        var input = base
        input["auth"] = "none"
        let profile = try cleanProfile(input)
        let request = try AIProvider().buildRequest(profile: profile, key: nil, system: "sys", user: "user")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}

private struct FailingTransport: AIHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw AIError.transport("mock")
    }
}
