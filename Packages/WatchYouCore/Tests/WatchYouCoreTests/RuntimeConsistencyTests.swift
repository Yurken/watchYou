import XCTest
@testable import WatchYouCore

final class RuntimeConsistencyTests: XCTestCase {
    private var tz: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }

    private func fact(id: String, value: Double, start: Date, end: Date) -> EvidenceFact {
        EvidenceFact(
            id: id,
            scope: "sleep",
            metric: "睡眠时长",
            value: value,
            unit: "min",
            sampleCount: 1,
            window: TimeWindow(start: start, end: end, timeZone: tz),
            sourceRef: "health",
            synthetic: false
        )
    }

    private func packet(facts: [EvidenceFact], question: String? = nil) -> EvidencePacket {
        let window = inferenceObservationWindow(facts: facts, lastNight: nil, timeZone: tz)
        return EvidencePacket(
            task: "today",
            synthetic: false,
            window: window,
            baselineValidDays: 7,
            facts: facts,
            question: question
        )
    }

    private func profile() throws -> AIProviderProfile {
        try cleanProfile([
            "id": "default",
            "name": "t",
            "baseURL": "https://model.example/v1",
            "protocol": "chat",
            "model": "test-model",
            "auth": "bearer",
            "maxTokens": 1200,
            "tokenField": "max_tokens",
            "timeout": 45,
            "allowLocalHTTP": false
        ])
    }

    func testCanonicalHashChangesWhenFactValueChanges() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_003_600)
        let p = try profile()
        let a = packet(facts: [fact(id: "S1", value: 400, start: start, end: end)])
        let b = packet(facts: [fact(id: "S1", value: 446, start: start, end: end)])
        let ka = makeInferenceCacheKey(packet: a, contextText: "", profile: p, promptVersion: "1", sourcePolicyVersion: "1", consentVersion: "c", generation: 1)
        let kb = makeInferenceCacheKey(packet: b, contextText: "", profile: p, promptVersion: "1", sourcePolicyVersion: "1", consentVersion: "c", generation: 1)
        XCTAssertNotEqual(ka.inputHash, kb.inputHash)
    }

    func testCanonicalHashIgnoresFactOrder() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_003_600)
        let p = try profile()
        let f1 = fact(id: "S1", value: 400, start: start, end: end)
        let f2 = fact(id: "H1", value: 68, start: start, end: end)
        let ka = makeInferenceCacheKey(packet: packet(facts: [f1, f2]), contextText: "x", profile: p, promptVersion: "1", sourcePolicyVersion: "1", consentVersion: "c", generation: 1)
        let kb = makeInferenceCacheKey(packet: packet(facts: [f2, f1]), contextText: "x", profile: p, promptVersion: "1", sourcePolicyVersion: "1", consentVersion: "c", generation: 1)
        XCTAssertEqual(ka.inputHash, kb.inputHash)
    }

    func testCanonicalHashChangesForModelContextAndConsent() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_003_600)
        let facts = [fact(id: "S1", value: 400, start: start, end: end)]
        let p = try profile()
        let base = makeInferenceCacheKey(packet: packet(facts: facts), contextText: "", profile: p, promptVersion: "1", sourcePolicyVersion: "1", consentVersion: "c", generation: 1)
        let otherModel = try cleanProfile([
            "id": "default",
            "name": "t",
            "baseURL": "https://model.example/v1",
            "protocol": "chat",
            "model": "other-model",
            "auth": "bearer",
            "maxTokens": 1200,
            "tokenField": "max_tokens",
            "timeout": 45,
            "allowLocalHTTP": false
        ])
        XCTAssertNotEqual(
            base.inputHash,
            makeInferenceCacheKey(packet: packet(facts: facts), contextText: "", profile: otherModel, promptVersion: "1", sourcePolicyVersion: "1", consentVersion: "c", generation: 1).inputHash
        )
        XCTAssertNotEqual(
            base.inputHash,
            makeInferenceCacheKey(packet: packet(facts: facts), contextText: "喝了咖啡", profile: p, promptVersion: "1", sourcePolicyVersion: "1", consentVersion: "c", generation: 1).inputHash
        )
        XCTAssertNotEqual(
            base.consentVersion,
            makeInferenceCacheKey(packet: packet(facts: facts), contextText: "", profile: p, promptVersion: "1", sourcePolicyVersion: "1", consentVersion: "other", generation: 1).consentVersion
        )
        XCTAssertNotEqual(
            base,
            makeInferenceCacheKey(packet: packet(facts: facts), contextText: "", profile: p, promptVersion: "1", sourcePolicyVersion: "1", consentVersion: "c", generation: 2)
        )
    }

    func testCanonicalHashChangesWhenFactMetadataChanges() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_003_600)
        let p = try profile()
        func key(_ item: EvidenceFact) -> String {
            makeInferenceCacheKey(
                packet: packet(facts: [item]),
                contextText: "",
                profile: p,
                promptVersion: "1",
                sourcePolicyVersion: "1",
                consentVersion: "c",
                generation: 1
            ).inputHash
        }
        let base = fact(id: "S1", value: 400, start: start, end: end)
        XCTAssertNotEqual(key(base), key(EvidenceFact(
            id: base.id, scope: base.scope, metric: base.metric, value: base.value, unit: "count",
            sampleCount: base.sampleCount, window: base.window, sourceRef: base.sourceRef, synthetic: false
        )))
        XCTAssertNotEqual(key(base), key(EvidenceFact(
            id: base.id, scope: base.scope, metric: base.metric, value: base.value, unit: base.unit,
            sampleCount: 9, window: base.window, sourceRef: base.sourceRef, synthetic: false
        )))
        XCTAssertNotEqual(key(base), key(EvidenceFact(
            id: base.id, scope: base.scope, metric: base.metric, value: base.value, unit: base.unit,
            sampleCount: base.sampleCount, window: base.window, sourceRef: "watch", synthetic: false
        )))
        XCTAssertNotEqual(key(base), key(fact(id: "S1", value: 400, start: start, end: end.addingTimeInterval(60))))
        XCTAssertNotEqual(
            makeInferenceCacheKey(packet: packet(facts: [base]), contextText: "", profile: p, promptVersion: "1", sourcePolicyVersion: "1", consentVersion: "c", generation: 1).inputHash,
            makeInferenceCacheKey(packet: packet(facts: [base]), contextText: "", profile: p, promptVersion: "2", sourcePolicyVersion: "1", consentVersion: "c", generation: 1).inputHash
        )
    }

    func testObservationWindowDoesNotUseCallTime() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 1_003_600)
        let facts = [fact(id: "S1", value: 400, start: start, end: end)]
        let first = inferenceObservationWindow(facts: facts, lastNight: nil, timeZone: tz)
        let second = inferenceObservationWindow(facts: facts, lastNight: nil, timeZone: tz)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.start, start)
        XCTAssertEqual(first.end, end)
        let empty = inferenceObservationWindow(facts: [], lastNight: nil, timeZone: tz)
        XCTAssertEqual(empty.start, Date(timeIntervalSince1970: 0))
    }

    func testCacheHitPreservesOriginalGeneratedAt() {
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        let served = Date(timeIntervalSince1970: 1_700_003_600)
        let result = AIResult(summary: "s", evidenceIds: ["S1"], uncertainties: ["u"], suggestions: [], emotion: nil)
        let persisted = applyCachedInference(
            result: result,
            facts: [],
            model: "m",
            mode: "live",
            originalGeneratedAt: original,
            servedAt: served,
            cacheHit: true,
            inputHash: "h",
            window: TimeWindow(start: original, end: original, timeZone: tz),
            observedAt: original,
            task: "today"
        )
        XCTAssertEqual(persisted.generatedAt, original)
        XCTAssertEqual(persisted.servedAt, served)
        XCTAssertEqual(persisted.cacheHit, true)
    }

    func testCacheExpiresAndEvicts() async {
        let cache = InferenceCache(ttl: 10, capacity: 2)
        let now = Date(timeIntervalSince1970: 1_000)
        let key = makeInferenceCacheKey(
            packet: packet(facts: [fact(id: "S1", value: 1, start: now, end: now)]),
            contextText: "",
            profile: try! profile(),
            promptVersion: "1",
            sourcePolicyVersion: "1",
            consentVersion: "c",
            generation: 1
        )
        let record = InferenceRecord(
            result: AIResult(summary: "s", evidenceIds: ["S1"], uncertainties: ["u"], suggestions: [], emotion: nil),
            evidenceIDs: ["S1"],
            generation: 1,
            originalGeneratedAt: now
        )
        await cache.put(record, for: key, now: now)
        let hit = await cache.get(key, now: now.addingTimeInterval(5))
        XCTAssertEqual(hit?.originalGeneratedAt, now)
        let expired = await cache.get(key, now: now.addingTimeInterval(11))
        XCTAssertNil(expired)
    }

    func testCacheEvictsOldestWhenOverCapacity() async throws {
        let cache = InferenceCache(ttl: 1_000, capacity: 2)
        let now = Date(timeIntervalSince1970: 2_000)
        let p = try profile()
        func key(_ value: Double) -> InferenceCacheKey {
            makeInferenceCacheKey(
                packet: packet(facts: [fact(id: "S1", value: value, start: now, end: now)]),
                contextText: "",
                profile: p,
                promptVersion: "1",
                sourcePolicyVersion: "1",
                consentVersion: "c",
                generation: 1
            )
        }
        func record(_ offset: TimeInterval) -> InferenceRecord {
            InferenceRecord(
                result: AIResult(summary: "s", evidenceIds: ["S1"], uncertainties: ["u"], suggestions: [], emotion: nil),
                evidenceIDs: ["S1"],
                generation: 1,
                originalGeneratedAt: now.addingTimeInterval(offset)
            )
        }
        let k1 = key(1)
        let k2 = key(2)
        let k3 = key(3)
        await cache.put(record(0), for: k1, now: now)
        await cache.put(record(1), for: k2, now: now)
        await cache.put(record(2), for: k3, now: now)
        let first = await cache.get(k1, now: now)
        let second = await cache.get(k2, now: now)
        let third = await cache.get(k3, now: now)
        XCTAssertNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)
    }

    func testStaleRequestIsNotCommitted() {
        let window = TimeWindow(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1), timeZone: tz)
        func context(id: UUID, generation: Int) -> InferenceRequestContext {
            InferenceRequestContext(
                requestID: id,
                generation: generation,
                task: "today",
                profileID: "default",
                model: "m",
                normalizedEndpoint: "https://model.example/v1",
                protocolName: "chat",
                authType: "bearer",
                consentVersion: "c",
                inputHash: "h",
                window: window,
                createdAt: Date()
            )
        }
        let first = context(id: UUID(), generation: 1)
        XCTAssertTrue(shouldCommitInference(context: first, currentGeneration: 1, currentRequestID: first.requestID))
        XCTAssertFalse(shouldCommitInference(context: first, currentGeneration: 2, currentRequestID: first.requestID))
        XCTAssertFalse(shouldCommitInference(context: first, currentGeneration: 1, currentRequestID: UUID()))
        XCTAssertFalse(shouldCommitInference(context: first, currentGeneration: 1, currentRequestID: nil))
        XCTAssertFalse(shouldClearBusy(finishing: first.requestID, currentRequestID: UUID()))
        XCTAssertTrue(shouldClearBusy(finishing: first.requestID, currentRequestID: first.requestID))

        var generation = 1
        var liveRequestID: UUID? = first.requestID
        var committed: [UUID] = []
        generation += 1
        liveRequestID = nil
        let second = context(id: UUID(), generation: generation)
        liveRequestID = second.requestID
        if shouldCommitInference(context: first, currentGeneration: generation, currentRequestID: liveRequestID) {
            committed.append(first.requestID)
        }
        if shouldClearBusy(finishing: first.requestID, currentRequestID: liveRequestID) {
            liveRequestID = nil
        }
        XCTAssertTrue(committed.isEmpty)
        XCTAssertEqual(liveRequestID, second.requestID)
        if shouldCommitInference(context: second, currentGeneration: generation, currentRequestID: liveRequestID) {
            committed.append(second.requestID)
        }
        XCTAssertEqual(committed, [second.requestID])
    }

    func testHTTPRedirectStatusesAreRejected() async throws {
        let p = try profile()
        for code in [301, 302, 303, 307, 308] {
            do {
                _ = try await AIProvider(transport: StatusTransport(statusCode: code)).generate(profile: p, key: "K", system: "s", user: "u")
                XCTFail("\(code) 应拒绝")
            } catch let error as AIError {
                guard case .badURL(let message) = error else {
                    XCTFail("\(code) 应为 badURL: \(error)")
                    return
                }
                XCTAssertTrue(message.contains("重定向"), "\(code) 应说明重定向")
            }
        }
    }

    func testListModelsUsesTransportAndRejectsRedirect() async throws {
        let p = try profile()
        let payload = try JSONSerialization.data(withJSONObject: ["data": [["id": "m1"], ["id": "m2"]]])
        let ids = try await AIProvider(transport: StatusTransport(statusCode: 200, data: payload)).listModels(profile: p, key: "K")
        XCTAssertEqual(ids, ["m1", "m2"])
        do {
            _ = try await AIProvider(transport: StatusTransport(statusCode: 307)).listModels(profile: p, key: "K")
            XCTFail("307 应拒绝")
        } catch let error as AIError {
            guard case .badURL = error else { XCTFail("应为 badURL: \(error)"); return }
        }
    }

    func testSessionDelegateDoesNotFollowRedirect() async throws {
        try await assertRedirectBlocked(authorization: "Bearer secret-token", apiKey: "probe-key")
        try await assertRedirectBlocked(authorization: "Bearer secret-token", apiKey: nil)
        try await assertRedirectBlocked(authorization: nil, apiKey: "probe-key")
        try await assertRedirectBlocked(authorization: nil, apiKey: nil)
    }

    private func assertRedirectBlocked(authorization: String?, apiKey: String?) async throws {
        var request = URLRequest(url: URL(string: "https://bound.example/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        RedirectProbeProtocol.reset()
        let followConfig = URLSessionConfiguration.ephemeral
        followConfig.protocolClasses = [RedirectProbeProtocol.self]
        followConfig.timeoutIntervalForRequest = 2
        followConfig.timeoutIntervalForResource = 2
        let following = URLSession(configuration: followConfig)
        _ = try? await following.data(for: request)
        following.invalidateAndCancel()

        RedirectProbeProtocol.reset()
        let blockConfig = URLSessionConfiguration.ephemeral
        blockConfig.protocolClasses = [RedirectProbeProtocol.self]
        blockConfig.timeoutIntervalForRequest = 2
        blockConfig.timeoutIntervalForResource = 2
        let session = makeNonRedirectingURLSession(configuration: blockConfig)
        let transport = URLSessionTransport(session: session)
        let (_, response) = try await transport.data(for: request)
        session.invalidateAndCancel()
        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(response.url, request.url)
        XCTAssertTrue(RedirectProbeProtocol.paths.contains("/v1/chat/completions"))
        XCTAssertFalse(RedirectProbeProtocol.paths.contains("/redirect-target"), "跳转目标不得收到请求")
        XCTAssertFalse(RedirectProbeProtocol.targetSawAuthorization)
        XCTAssertFalse(RedirectProbeProtocol.targetSawAPIKey)
    }
}

private final class StatusTransport: AIHTTPTransport, @unchecked Sendable {
    let statusCode: Int
    let data: Data

    init(statusCode: Int, data: Data = Data()) {
        self.statusCode = statusCode
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://evil.example/steal"]
        )!
        return (data, response)
    }
}

private final class RedirectProbeProtocol: URLProtocol, @unchecked Sendable {
    private struct ProbeState {
        var paths: [String] = []
        var targetSawAuthorization = false
        var targetSawAPIKey = false
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var probeState = ProbeState()

    static var paths: [String] {
        lock.withLock { probeState.paths }
    }
    static var targetSawAuthorization: Bool {
        lock.withLock { probeState.targetSawAuthorization }
    }
    static var targetSawAPIKey: Bool {
        lock.withLock { probeState.targetSawAPIKey }
    }

    static func reset() {
        lock.withLock { probeState = ProbeState() }
    }

    private static func record(path: String) {
        lock.withLock { probeState.paths.append(path) }
    }

    private static func recordTargetCredentials(authorization: Bool, apiKey: Bool) {
        lock.withLock {
            if authorization { probeState.targetSawAuthorization = true }
            if apiKey { probeState.targetSawAPIKey = true }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.record(path: path)
        if path.contains("redirect-target") {
            Self.recordTargetCredentials(
                authorization: request.value(forHTTPHeaderField: "Authorization") != nil,
                apiKey: request.value(forHTTPHeaderField: "x-api-key") != nil
            )
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let location = "https://evil.example/redirect-target"
        var redirected = URLRequest(url: URL(string: location)!)
        redirected.httpMethod = request.httpMethod
        redirected.allHTTPHeaderFields = request.allHTTPHeaderFields
        redirected.httpBody = request.httpBody
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": location]
        )!
        client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
