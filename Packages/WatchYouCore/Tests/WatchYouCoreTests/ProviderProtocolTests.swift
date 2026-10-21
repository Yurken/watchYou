import XCTest
@testable import WatchYouCore

/// M1 验收清单覆盖：A14 三协议适配、A22 401/403/429/超时/非 JSON 错误映射、A23 截断拒绝、A18 取消/过期任务不覆盖。
final class ProviderProtocolTests: XCTestCase {
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

    private func profile(_ overrides: [String: Any]) throws -> AIProviderProfile {
        try cleanProfile(base.merging(overrides, uniquingKeysWith: { $1 }))
    }

    private func body(from request: URLRequest) throws -> [String: Any] {
        let data = request.httpBody ?? Data()
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    // MARK: - Request shape

    func testChatCompletionRequest() throws {
        let p = try profile([:])
        let request = try AIProvider().buildRequest(profile: p, key: "TEST", system: "sys", user: "user")
        XCTAssertEqual(request.url?.absoluteString, "https://model.example/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer TEST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try body(from: request)
        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["max_tokens"] as? Int, 1200)
        XCTAssertNil(body["temperature"])
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?[0]["role"], "system")
        XCTAssertEqual(messages?[1]["role"], "user")
    }

    func testChatTokenFieldSelectable() throws {
        let p = try profile(["tokenField": "max_completion_tokens"])
        let request = try AIProvider().buildRequest(profile: p, key: "TEST", system: "sys", user: "user")
        let body = try body(from: request)
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 1200)
        XCTAssertNil(body["max_tokens"])
    }

    func testOptionalTemperatureIncluded() throws {
        let p = try profile(["temperature": 0.0])
        let request = try AIProvider().buildRequest(profile: p, key: "TEST", system: "sys", user: "user")
        let body = try body(from: request)
        XCTAssertEqual(body["temperature"] as? Double, 0)
    }

    func testResponsesRequestShape() throws {
        let p = try profile(["protocol": "responses"])
        let request = try AIProvider().buildRequest(profile: p, key: "TEST", system: "sys", user: "user")
        XCTAssertEqual(request.url?.absoluteString, "https://model.example/v1/responses")
        let body = try body(from: request)
        XCTAssertEqual(body["instructions"] as? String, "sys")
        XCTAssertEqual(body["input"] as? String, "user")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["max_output_tokens"] as? Int, 1200)
    }

    func testAnthropicRequestShape() throws {
        let p = try profile(["protocol": "anthropic", "auth": "x-api-key"])
        let request = try AIProvider().buildRequest(profile: p, key: "TEST", system: "sys", user: "user")
        XCTAssertEqual(request.url?.absoluteString, "https://model.example/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "TEST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let body = try body(from: request)
        XCTAssertEqual(body["system"] as? String, "sys")
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.first?["role"], "user")
    }

    // MARK: - Extract text success

    func testChatExtractText() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": "ok"], "finish_reason": "stop"]]
        ])
        XCTAssertEqual(try extractText(protocolName: "chat", data: data), "ok")
    }

    func testResponsesExtractTextFromOutputBlocks() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "output": [["content": [["type": "output_text", "text": "ok"]]]]
        ])
        XCTAssertEqual(try extractText(protocolName: "responses", data: data), "ok")
    }

    func testResponsesOutputTextField() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "output_text": "ok"
        ])
        XCTAssertEqual(try extractText(protocolName: "responses", data: data), "ok")
    }

    func testAnthropicExtractText() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "content": [["type": "text", "text": "ok"]],
            "stop_reason": "end_turn"
        ])
        XCTAssertEqual(try extractText(protocolName: "anthropic", data: data), "ok")
    }

    // MARK: - Truncation

    func testChatLengthTruncationRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": "partial"], "finish_reason": "length"]]
        ])
        XCTAssertThrowsError(try extractText(protocolName: "chat", data: data)) { error in
            XCTAssertEqual((error as? AIError)?.localizedDescription, AIError.truncated.localizedDescription)
        }
    }

    func testResponsesIncompleteRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "output_text": "partial",
            "status": "incomplete"
        ])
        XCTAssertThrowsError(try extractText(protocolName: "responses", data: data)) { error in
            XCTAssertEqual((error as? AIError)?.localizedDescription, AIError.truncated.localizedDescription)
        }
    }

    func testAnthropicMaxTokensRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "content": [["type": "text", "text": "partial"]],
            "stop_reason": "max_tokens"
        ])
        XCTAssertThrowsError(try extractText(protocolName: "anthropic", data: data)) { error in
            XCTAssertEqual((error as? AIError)?.localizedDescription, AIError.truncated.localizedDescription)
        }
    }

    // MARK: - HTTP error mapping

    func test401MappedToUnauthorized() async throws {
        let transport = StubTransport(statusCode: 401)
        let p = try profile([:])
        await assertThrowsError(try await AIProvider(transport: transport).generate(profile: p, key: "K", system: "s", user: "u")) { error in
            guard case AIError.unauthorized = error else { XCTFail("应为 unauthorized: \(error)"); return }
        }
    }

    func test403MappedToUnauthorized() async throws {
        let transport = StubTransport(statusCode: 403)
        let p = try profile([:])
        await assertThrowsError(try await AIProvider(transport: transport).generate(profile: p, key: "K", system: "s", user: "u")) { error in
            guard case AIError.unauthorized = error else { XCTFail("应为 unauthorized: \(error)"); return }
        }
    }

    func test429MappedToRateLimited() async throws {
        let transport = StubTransport(statusCode: 429)
        let p = try profile([:])
        await assertThrowsError(try await AIProvider(transport: transport).generate(profile: p, key: "K", system: "s", user: "u")) { error in
            guard case AIError.rateLimited = error else { XCTFail("应为 rateLimited: \(error)"); return }
        }
    }

    func test500MappedToTransport() async throws {
        let transport = StubTransport(statusCode: 500)
        let p = try profile([:])
        await assertThrowsError(try await AIProvider(transport: transport).generate(profile: p, key: "K", system: "s", user: "u")) { error in
            guard case AIError.transport = error else { XCTFail("应为 transport: \(error)"); return }
        }
    }

    func testNonJSONErrorMappedToInvalidJSON() async throws {
        let transport = StubTransport(data: Data("not json".utf8))
        let p = try profile([:])
        await assertThrowsError(try await AIProvider(transport: transport).generate(profile: p, key: "K", system: "s", user: "u")) { error in
            guard case AIError.invalidJSON = error else { XCTFail("应为 invalidJSON: \(error)"); return }
        }
    }

    func testTimeoutUsesProfileTimeout() throws {
        let p = try profile(["timeout": 7])
        let request = try AIProvider().buildRequest(profile: p, key: "K", system: "s", user: "u")
        XCTAssertEqual(request.timeoutInterval, 7, accuracy: 0.1)
    }

    func testCancellationPropagates() async throws {
        let p = try profile([:])
        let transport = CancellingTransport()
        let task = Task {
            try await AIProvider(transport: transport).generate(profile: p, key: "K", system: "s", user: "u")
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("取消后不应成功")
        } catch is CancellationError {
            // expected
        }
    }

    func testRedirectRejected() async throws {
        let p = try profile([:])
        let transport = StubTransport(statusCode: 200, finalURL: URL(string: "https://other.example/v1/chat/completions")!)
        await assertThrowsError(try await AIProvider(transport: transport).generate(profile: p, key: "K", system: "s", user: "u")) { error in
            guard case AIError.badURL = error else { XCTFail("应为 badURL: \(error)"); return }
        }
    }

    func testSafeErrorDoesNotExposeServerResponse() {
        let text = safeError(AIError.transport("Failed to fetch"))
        XCTAssertTrue(text.contains("CORS"), "应给出用户-facing 网络检查提示")
        XCTAssertEqual(safeError(CancellationError()), "请求已取消或超时；未生成新结论")
    }
}

private func assertThrowsError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (any Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("应抛出错误")
    } catch {
        handler(error)
    }
}

private final class StubTransport: AIHTTPTransport, @unchecked Sendable {
    private let statusCode: Int
    private let data: Data
    private let finalURL: URL?

    init(statusCode: Int = 200, data: Data = Data(), finalURL: URL? = nil) {
        self.statusCode = statusCode
        self.data = data
        self.finalURL = finalURL
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = finalURL ?? request.url!
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}

private final class CancellingTransport: AIHTTPTransport, @unchecked Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(nanoseconds: 100_000_000)
        if Task.isCancelled { throw CancellationError() }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
