import Foundation

/// Determine whether a host is an explicitly allowed local/private address.
public func isPrivateHost(_ host: String) -> Bool {
    let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if h == "localhost" || h == "::1" { return true }

    let pattern = "^\\d{1,3}(?:\\.\\d{1,3}){3}$"
    guard h.range(of: pattern, options: .regularExpression) != nil else { return false }

    let octets = h.split(separator: ".").compactMap { Int($0) }
    guard octets.count == 4, octets.allSatisfy({ $0 <= 255 }) else { return false }

    if octets[0] == 127 || octets[0] == 10 { return true }
    if octets[0] == 192 && octets[1] == 168 { return true }
    if octets[0] == 172 && (16...31).contains(octets[1]) { return true }
    return false
}

/// Normalize a base URL: enforce HTTPS, reject embedded credentials/queries/fragments,
/// strip trailing slashes and provider-specific suffixes, and preserve proxy prefixes.
public func normalizeBase(_ input: String, allowLocalHTTP: Bool = false) throws -> String {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    guard trimmed.count <= 2048 else { throw EndpointError.oversized("URL 过长") }

    // URLComponents rejects some non-standard schemes; fall back to URL to catch javascript: etc.
    let parsedURL = URL(string: trimmed)
    if let url = parsedURL,
       let scheme = url.scheme?.lowercased(),
       scheme != "https", scheme != "http" {
        throw EndpointError.invalidURL("要求 HTTPS；仅显式允许的本机或私网测试地址可用 HTTP")
    }

    guard let components = URLComponents(string: trimmed),
          let scheme = components.scheme?.lowercased(),
          let host = components.host, !host.isEmpty else {
        throw EndpointError.invalidURL("URL 无效，请填写包含 https:// 的完整地址")
    }

    if components.user != nil || components.password != nil {
        throw EndpointError.invalidURL("URL 不可包含用户名、密码、查询参数或片段；密钥请单独填写")
    }
    if components.query != nil || components.fragment != nil {
        throw EndpointError.invalidURL("URL 不可包含用户名、密码、查询参数或片段；密钥请单独填写")
    }

    let isPrivate = isPrivateHost(host)
    guard scheme == "https" || (scheme == "http" && allowLocalHTTP && isPrivate) else {
        throw EndpointError.invalidURL("要求 HTTPS；仅显式允许的本机或私网测试地址可用 HTTP")
    }

    var path = components.path
    while path.hasSuffix("/") && path.count > 1 {
        path.removeLast()
    }
    let suffixPattern = "/(chat/completions|responses|messages|models)$"
    path = path.replacingOccurrences(of: suffixPattern, with: "", options: .regularExpression, range: nil)

    var origin = "\(scheme)://\(host.lowercased())"
    if let port = components.port {
        origin += ":\(port)"
    }

    return path == "/" ? origin : origin + path
}

/// Build the full endpoint URL for a profile and optional API kind (`generate` or `models`).
public func endpoint(for profile: AIProviderProfile, kind: String = "generate") throws -> String {
    let suffix: String
    if kind == "models" {
        suffix = "/models"
    } else {
        switch profile.protocolName {
        case "chat": suffix = "/chat/completions"
        case "responses": suffix = "/responses"
        case "anthropic": suffix = "/messages"
        default: throw EndpointError.unsupportedProtocol("不支持的协议")
        }
    }
    return try normalizeBase(profile.baseURL, allowLocalHTTP: profile.allowLocalHTTP) + suffix
}

public enum EndpointError: Error, Equatable {
    case oversized(String)
    case invalidURL(String)
    case unsupportedProtocol(String)
}
