import Foundation

public let AIProtocols = ["chat", "responses", "anthropic"]
public let AIModules = [
    "today", "mood", "sleep", "heart", "recovery",
    "activity", "habits", "trends", "assistant"
]
public let AIDataScopes = ["sleep", "heart", "activity", "habits", "context"]

/// A single AI service profile.
public struct AIProviderProfile: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let baseURL: String
    public let protocolName: String
    public let model: String
    public let auth: String
    public let temperature: Double?
    public let maxTokens: Int
    public let tokenField: String
    public let timeout: Int
    public let allowLocalHTTP: Bool

    public init(
        id: String,
        name: String,
        baseURL: String,
        protocolName: String,
        model: String,
        auth: String,
        temperature: Double?,
        maxTokens: Int,
        tokenField: String,
        timeout: Int,
        allowLocalHTTP: Bool
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.protocolName = protocolName
        self.model = model
        self.auth = auth
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.tokenField = tokenField
        self.timeout = timeout
        self.allowLocalHTTP = allowLocalHTTP
    }
}

/// Full AI configuration.
public struct AIConfig: Equatable, Sendable, Codable {
    public let version: Int
    public let active: String
    public let profiles: [AIProviderProfile]
    public let mode: String
    public let auto: Bool
    public let dailyLimit: Int
    public let modules: [String: Bool]
    public let scopes: [String: Bool]

    public init(
        version: Int,
        active: String,
        profiles: [AIProviderProfile],
        mode: String,
        auto: Bool,
        dailyLimit: Int,
        modules: [String: Bool],
        scopes: [String: Bool]
    ) {
        self.version = version
        self.active = active
        self.profiles = profiles
        self.mode = mode
        self.auto = auto
        self.dailyLimit = dailyLimit
        self.modules = modules
        self.scopes = scopes
    }
}

public func defaultAIProfile() -> AIProviderProfile {
    AIProviderProfile(
        id: "default",
        name: "我的 AI 服务",
        baseURL: "",
        protocolName: "chat",
        model: "",
        auth: "bearer",
        temperature: nil,
        maxTokens: 1200,
        tokenField: "max_tokens",
        timeout: 45,
        allowLocalHTTP: false
    )
}

public func defaultAIConfig() -> AIConfig {
    AIConfig(
        version: 2,
        active: "default",
        profiles: [defaultAIProfile()],
        mode: "demo",
        auto: true,
        dailyLimit: 20,
        modules: Dictionary(uniqueKeysWithValues: AIModules.map { ($0, true) }),
        scopes: [
            "sleep": true,
            "heart": true,
            "activity": true,
            "habits": false,
            "context": false
        ]
    )
}

/// Validate and normalize a single profile. Secret fields such as `apiKey` are explicitly dropped.
public func cleanProfile(_ input: [String: Any]) throws -> AIProviderProfile {
    guard !input.isEmpty else { throw AIConfigError.invalidProfile("服务配置无效") }

    var id = "default"
    if let rawID = input["id"] as? String,
       rawID.range(of: "^[\\w-]{1,80}$", options: .regularExpression) != nil {
        id = rawID
    }

    let name = (input["name"] as? String)?.prefix(60).description ?? "我的 AI 服务"

    let protocolName = AIProtocols.contains(input["protocol"] as? String ?? "") ? (input["protocol"] as! String) : "chat"
    let allowLocalHTTP = input["allowLocalHTTP"] as? Bool ?? false

    let rawBase = (input["baseURL"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    let baseURL = rawBase.isEmpty ? "" : try normalizeBase(rawBase, allowLocalHTTP: allowLocalHTTP)

    let model = (input["model"] as? String)?.trimmingCharacters(in: .whitespaces).prefix(180).description ?? ""

    let authValue = input["auth"] as? String
    let auth = ["bearer", "x-api-key", "none"].contains(authValue) ? authValue! : "bearer"

    let temperature: Double?
    if let t = input["temperature"] as? Double {
        guard t >= 0, t <= 2 else { throw AIConfigError.invalidTemperature("Temperature 需留空或为 0–2") }
        temperature = t
    } else if let t = input["temperature"] as? String, t.isEmpty {
        temperature = nil
    } else if input["temperature"] == nil || (input["temperature"] is NSNull) {
        temperature = nil
    } else {
        throw AIConfigError.invalidTemperature("Temperature 需留空或为 0–2")
    }

    let maxTokens = input["maxTokens"] as? Int ?? 1200
    guard maxTokens >= 64, maxTokens <= 16000 else {
        throw AIConfigError.invalidMaxTokens("输出上限需为 64–16000 的整数")
    }

    let timeout = input["timeout"] as? Int ?? 45
    guard timeout >= 5, timeout <= 180 else {
        throw AIConfigError.invalidTimeout("超时需为 5–180 秒的整数")
    }

    let tokenField = (input["tokenField"] as? String) == "max_completion_tokens" ? "max_completion_tokens" : "max_tokens"

    return AIProviderProfile(
        id: id,
        name: name,
        baseURL: baseURL,
        protocolName: protocolName,
        model: model,
        auth: auth,
        temperature: temperature,
        maxTokens: maxTokens,
        tokenField: tokenField,
        timeout: timeout,
        allowLocalHTTP: allowLocalHTTP
    )
}

/// Validate and sanitize a full configuration. Backups are always restored to demo mode.
public func sanitizeConfig(_ input: [String: Any]) throws -> AIConfig {
    guard (input["version"] as? Int) == 2,
          let profilesArray = input["profiles"] as? [[String: Any]],
          !profilesArray.isEmpty,
          profilesArray.count <= 8 else {
        throw AIConfigError.invalidConfig("AI 配置版本或服务数量无效")
    }

    let profiles = try profilesArray.map(cleanProfile)
    guard Set(profiles.map(\.id)).count == profiles.count else {
        throw AIConfigError.duplicateID("服务 ID 重复")
    }

    let active = profiles.contains(where: { $0.id == input["active"] as? String })
        ? (input["active"] as! String)
        : profiles[0].id

    let rawLimit = input["dailyLimit"] as? Int
    let dailyLimit = (rawLimit != nil && rawLimit! >= 1 && rawLimit! <= 200) ? rawLimit! : 20

    var modules = Dictionary(uniqueKeysWithValues: AIModules.map { ($0, true) })
    if let inputModules = input["modules"] as? [String: Bool] {
        for key in AIModules { modules[key] = inputModules[key] != false }
    }

    var scopes = [
        "sleep": true,
        "heart": true,
        "activity": true,
        "habits": false,
        "context": false
    ]
    if let inputScopes = input["scopes"] as? [String: Bool] {
        for key in AIDataScopes { scopes[key] = inputScopes[key] == true }
    }

    return AIConfig(
        version: 2,
        active: active,
        profiles: profiles,
        mode: "demo",
        auto: (input["auto"] as? Bool) != false,
        dailyLimit: dailyLimit,
        modules: modules,
        scopes: scopes
    )
}

public enum AIConfigError: Error, Equatable {
    case invalidProfile(String)
    case invalidTemperature(String)
    case invalidMaxTokens(String)
    case invalidTimeout(String)
    case invalidConfig(String)
    case duplicateID(String)
}

public extension AIConfig {
    func replacing(
        active: String? = nil,
        profiles: [AIProviderProfile]? = nil,
        mode: String? = nil,
        auto: Bool? = nil,
        dailyLimit: Int? = nil,
        modules: [String: Bool]? = nil,
        scopes: [String: Bool]? = nil
    ) -> AIConfig {
        AIConfig(
            version: version,
            active: active ?? self.active,
            profiles: profiles ?? self.profiles,
            mode: mode ?? self.mode,
            auto: auto ?? self.auto,
            dailyLimit: dailyLimit ?? self.dailyLimit,
            modules: modules ?? self.modules,
            scopes: scopes ?? self.scopes
        )
    }

    var activeProfile: AIProviderProfile {
        profiles.first { $0.id == active } ?? profiles[0]
    }
}

public func profileDictionary(_ profile: AIProviderProfile) -> [String: Any] {
    var dict: [String: Any] = [
        "id": profile.id,
        "name": profile.name,
        "baseURL": profile.baseURL,
        "protocol": profile.protocolName,
        "model": profile.model,
        "auth": profile.auth,
        "maxTokens": profile.maxTokens,
        "tokenField": profile.tokenField,
        "timeout": profile.timeout,
        "allowLocalHTTP": profile.allowLocalHTTP
    ]
    if let temperature = profile.temperature {
        dict["temperature"] = temperature
    }
    return dict
}

public func configDictionary(_ config: AIConfig) -> [String: Any] {
    [
        "version": config.version,
        "active": config.active,
        "profiles": config.profiles.map(profileDictionary),
        "mode": config.mode,
        "auto": config.auto,
        "dailyLimit": config.dailyLimit,
        "modules": config.modules,
        "scopes": config.scopes
    ]
}

/// Load a stored configuration. Backups must pass `preserveMode: false` so restored copies stay in demo.
public func loadConfig(_ input: [String: Any], preserveMode: Bool) throws -> AIConfig {
    let sanitized = try sanitizeConfig(input)
    guard preserveMode, let mode = input["mode"] as? String, ["demo", "live"].contains(mode) else {
        return sanitized
    }
    return sanitized.replacing(mode: mode)
}
