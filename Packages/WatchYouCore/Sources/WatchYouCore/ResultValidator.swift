import Foundation

/// Validated and domain-enriched AI result.
public struct AIResult: Equatable, Sendable, Codable {
    public let summary: String
    public let evidenceIds: [String]
    public let uncertainties: [String]
    public let suggestions: [String]
    public let emotion: AIEmotion?

    public init(
        summary: String,
        evidenceIds: [String],
        uncertainties: [String],
        suggestions: [String],
        emotion: AIEmotion?
    ) {
        self.summary = summary
        self.evidenceIds = evidenceIds
        self.uncertainties = uncertainties
        self.suggestions = suggestions
        self.emotion = emotion
    }
}

public struct AIEmotion: Equatable, Sendable, Codable {
    public let status: String
    public let label: String
    public let arousal: String
    public let valence: String
    public let evidenceStrength: String?

    public init(
        status: String,
        label: String,
        arousal: String,
        valence: String,
        evidenceStrength: String?
    ) {
        self.status = status
        self.label = label
        self.arousal = arousal
        self.valence = valence
        self.evidenceStrength = evidenceStrength
    }
}

/// Parse and validate a raw model response against the evidence facts and context authorization.
public func parseResult(
    text: String,
    facts: [EvidenceFact],
    hasContext: Bool = false
) throws -> AIResult {
    guard text.count <= 128000 else {
        throw AIValidationError.oversized("模型返回过大或不是文本")
    }

    var source = text.trimmingCharacters(in: .whitespacesAndNewlines)
    source = source.replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
    source = source.replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)

    guard let data = source.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data),
          let object = json as? [String: Any] else {
        throw AIValidationError.invalidJSON("模型未返回有效 JSON，未把原始输出当作健康结论")
    }

    let factIDs = Set(facts.map(\.id))

    guard let summary = object["summary"] as? String,
          !summary.trimmingCharacters(in: .whitespaces).isEmpty,
          summary.count <= 1800 else {
        throw AIValidationError.invalidSummary("分析摘要格式无效")
    }

    guard let evidenceIds = object["evidenceIds"] as? [String],
          evidenceIds.count <= 30,
          evidenceIds.allSatisfy({ factIDs.contains($0) }) else {
        throw AIValidationError.unknownEvidence("分析引用了不存在的证据，结果已拦截")
    }

    if !facts.isEmpty && evidenceIds.isEmpty {
        throw AIValidationError.missingEvidence("分析没有引用观测依据")
    }

    let uncertainties = try validatedStringArray(object["uncertainties"], maxCount: 8, label: "建议或不确定性字段无效")
    let suggestions = try validatedStringArray(object["suggestions"], maxCount: 6, label: "建议或不确定性字段无效")

    var emotion: AIEmotion? = nil
    if let e = object["emotion"] as? [String: Any] {
        emotion = try validateEmotion(e, hasContext: hasContext)
    }

    return AIResult(
        summary: summary,
        evidenceIds: evidenceIds,
        uncertainties: uncertainties,
        suggestions: suggestions,
        emotion: emotion
    )
}

private func validatedStringArray(_ value: Any?, maxCount: Int, label: String) throws -> [String] {
    guard let array = value as? [String],
          array.count <= maxCount,
          array.allSatisfy({ $0.count <= 700 }) else {
        throw AIValidationError.invalidField(label)
    }
    return array
}

private let allowedArousal = Set(["low", "moderate", "high", "unknown"])
private let allowedValence = Set(["negative", "neutral", "positive", "unknown"])
private let physiologyOnlyLabels = Set(["可能偏平稳", "可能偏紧绷", "可能偏活跃", "暂无法判断"])

private func validateEmotion(_ e: [String: Any], hasContext: Bool) throws -> AIEmotion {
    guard let status = e["status"] as? String,
          ["estimated", "insufficient"].contains(status),
          let label = e["label"] as? String,
          label.count <= 40,
          let arousal = e["arousal"] as? String, allowedArousal.contains(arousal),
          let valence = e["valence"] as? String, allowedValence.contains(valence) else {
        throw AIValidationError.invalidEmotion("情绪字段格式无效")
    }

    if !hasContext && valence != "unknown" {
        throw AIValidationError.forbiddenValence("缺少可授权的情境证据，不能输出确定的愉悦度方向")
    }

    if !hasContext && !physiologyOnlyLabels.contains(label) {
        throw AIValidationError.forbiddenLabel("仅凭生理摘要不能断言具体心理情绪")
    }

    if status == "insufficient" && (arousal != "unknown" || valence != "unknown") {
        throw AIValidationError.insufficientWithCoordinates("数据不足状态不能带有确定的情绪坐标")
    }

    return AIEmotion(
        status: status,
        label: label,
        arousal: arousal,
        valence: valence,
        evidenceStrength: status == "estimated" ? "有限 · 未校准" : nil
    )
}

public enum AIValidationError: Error, Equatable {
    case oversized(String)
    case invalidJSON(String)
    case invalidSummary(String)
    case unknownEvidence(String)
    case missingEvidence(String)
    case invalidField(String)
    case invalidEmotion(String)
    case forbiddenValence(String)
    case forbiddenLabel(String)
    case insufficientWithCoordinates(String)
}
