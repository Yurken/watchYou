import Foundation

/// Transport abstraction so tests can mock network responses.
public protocol AIHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession-based transport. Refuses redirects by validating the response URL matches the request.
public final class URLSessionTransport: AIHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.transport("非 HTTP 响应")
        }
        if httpResponse.url != request.url {
            throw AIError.badURL("请求发生重定向")
        }
        return (data, httpResponse)
    }
}

/// Errors surfaced by the AI provider layer, with user-facing Chinese descriptions.
public enum AIError: Error, Equatable {
    case unconfigured(String)
    case badURL(String)
    case unauthorized
    case rateLimited
    case timeout
    case invalidJSON(String)
    case truncated
    case unknownEvidence(String)
    case refused(String)
    case transport(String)

    public var localizedDescription: String {
        switch self {
        case .unconfigured(let msg): return msg
        case .badURL(let msg): return msg
        case .unauthorized: return "认证失败，请检查 API Key 或认证方式"
        case .rateLimited: return "请求过于频繁，请稍后重试"
        case .timeout: return "请求超时"
        case .invalidJSON(let msg): return msg
        case .truncated: return "模型输出被截断"
        case .unknownEvidence(let msg): return msg
        case .refused(let msg): return msg
        case .transport(let msg): return "连接失败：\(msg)"
        }
    }
}

/// Capabilities vary by provider protocol.
public struct ProviderCapabilities: Equatable, Sendable {
    public let supportsModelList: Bool
    public let supportsJSONSchema: Bool
    public let supportsTemperature: Bool
    public let supportsStreaming: Bool
    public let tokenFields: [String]
}

public extension ProviderCapabilities {
    static let chat = ProviderCapabilities(
        supportsModelList: true,
        supportsJSONSchema: true,
        supportsTemperature: true,
        supportsStreaming: true,
        tokenFields: ["max_tokens", "max_completion_tokens"]
    )
    static let responses = ProviderCapabilities(
        supportsModelList: true,
        supportsJSONSchema: true,
        supportsTemperature: true,
        supportsStreaming: true,
        tokenFields: ["max_output_tokens"]
    )
    static let anthropic = ProviderCapabilities(
        supportsModelList: false,
        supportsJSONSchema: false,
        supportsTemperature: true,
        supportsStreaming: false,
        tokenFields: ["max_tokens"]
    )
}

/// High-level AI provider that builds requests, executes them, and extracts text.
public struct AIProvider: Sendable {
    public let transport: any AIHTTPTransport

    public init(transport: any AIHTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Generate text for the given profile, key, system template and user input.
    public func generate(profile: AIProviderProfile, key: String?, system: String, user: String) async throws -> String {
        let request = try buildRequest(profile: profile, key: key, system: system, user: user)
        let (data, response) = try await transport.data(for: request)
        if response.url != request.url {
            throw AIError.badURL("请求发生重定向")
        }
        try checkHTTPStatus(response)
        return try extractText(protocolName: profile.protocolName, data: data)
    }

    /// Build a provider-specific URLRequest.
    public func buildRequest(profile: AIProviderProfile, key: String?, system: String, user: String) throws -> URLRequest {
        guard !profile.model.isEmpty else {
            throw AIError.unconfigured("请填写 model")
        }
        if profile.auth != "none" && (key == nil || key!.isEmpty) {
            throw AIError.unconfigured("请填写当前服务的 API Key，或明确选择无认证")
        }

        let url = URL(string: try endpoint(for: profile, kind: "generate"))!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = TimeInterval(profile.timeout)
        request.httpShouldHandleCookies = false

        if let key = key, !key.isEmpty {
            if profile.auth == "bearer" {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            } else if profile.auth == "x-api-key" {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
            }
        }

        var body: [String: Any] = ["model": profile.model]
        switch profile.protocolName {
        case "responses":
            body["instructions"] = system
            body["input"] = user
            body["max_output_tokens"] = profile.maxTokens
            body["store"] = false
            body["stream"] = false
        case "anthropic":
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body["system"] = system
            body["messages"] = [["role": "user", "content": user]]
            body["max_tokens"] = profile.maxTokens
            body["stream"] = false
        default:
            body["messages"] = [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
            body[profile.tokenField] = profile.maxTokens
            body["stream"] = false
        }
        if let temperature = profile.temperature {
            body["temperature"] = temperature
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func checkHTTPStatus(_ response: HTTPURLResponse) throws {
        let code = response.statusCode
        guard (200..<300).contains(code) else {
            switch code {
            case 401, 403: throw AIError.unauthorized
            case 429: throw AIError.rateLimited
            case 504: throw AIError.timeout
            case 500..<600: throw AIError.transport("服务器错误 \(code)")
            default: throw AIError.transport("HTTP \(code)")
            }
        }
    }
}

/// Extract usable text from a provider response and detect truncation/refusal.
public func extractText(protocolName: String, data: Data) throws -> String {
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw AIError.invalidJSON("模型未返回有效 JSON，未把原始输出当作健康结论")
    }
    guard let json = object as? [String: Any] else {
        throw AIError.invalidJSON("模型未返回有效 JSON，未把原始输出当作健康结论")
    }

    var text = ""
    switch protocolName {
    case "responses":
        if let outputText = json["output_text"] as? String {
            text = outputText
        } else if let output = json["output"] as? [[String: Any]] {
            text = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { ($0["type"] as? String) == "output_text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        }
        if (json["status"] as? String) == "incomplete" {
            throw AIError.truncated
        }
    case "anthropic":
        if let content = json["content"] as? [[String: Any]] {
            text = content
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        }
        if (json["stop_reason"] as? String) == "max_tokens" {
            throw AIError.truncated
        }
    default:
        if let choice = (json["choices"] as? [[String: Any]])?.first {
            if (choice["finish_reason"] as? String) == "length" {
                throw AIError.truncated
            }
            if let message = choice["message"] as? [String: Any] {
                text = message["content"] as? String ?? ""
            }
        }
    }

    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return text
    }
    throw AIError.refused("返回中没有可用文本；模型可能拒绝回答或协议不匹配")
}


/// Sanitize an error for user-visible display without exposing server internals.
public func safeError(_ error: any Error) -> String {
    let message = String(describing: error)
    if error is CancellationError || message.localizedLowercase.contains("abort") {
        return "请求已取消或超时；未生成新结论"
    }
    if message.range(of: "fetch|network|load|cors", options: .regularExpression, range: nil, locale: nil) != nil {
        return "连接失败：请检查网络、HTTPS、浏览器 CORS 与服务地址；原型不会绕过安全限制"
    }
    return String(message.prefix(180))
}
