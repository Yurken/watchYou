import XCTest
@testable import WatchYouCore

/// M1 验收清单覆盖：A19 密钥隔离/不跨服务复用、A18 范围变化撤销旧授权、A11 缓存按证据失效、A25 相同输入不重复调用/并发安全。
final class CredentialConsentCacheTests: XCTestCase {
    private let tz = TimeZone(identifier: "Asia/Shanghai")!

    // MARK: - CredentialStore

    func testInMemoryCredentialIsolationByRecipient() throws {
        let store = InMemoryCredentialStore()
        let endpoint1 = credentialRecipient(normalizedEndpoint: "https://a.example/v1", authType: "bearer")
        let endpoint2 = credentialRecipient(normalizedEndpoint: "https://b.example/v1", authType: "bearer")
        try store.save(profileID: "p1", recipient: endpoint1, fingerprint: "1111", secret: "SECRET_A")
        try store.save(profileID: "p1", recipient: endpoint2, fingerprint: "2222", secret: "SECRET_B")
        XCTAssertEqual(try store.read(profileID: "p1", recipient: endpoint1)?.secret, "SECRET_A")
        XCTAssertEqual(try store.read(profileID: "p1", recipient: endpoint2)?.secret, "SECRET_B")
    }

    func testCredentialReadFailsForDifferentRecipient() throws {
        let store = InMemoryCredentialStore()
        let r1 = credentialRecipient(normalizedEndpoint: "https://a.example/v1", authType: "bearer")
        let r2 = credentialRecipient(normalizedEndpoint: "https://a.example/v1", authType: "x-api-key")
        try store.save(profileID: "p1", recipient: r1, fingerprint: "1111", secret: "SECRET")
        XCTAssertNil(try store.read(profileID: "p1", recipient: r2))
    }

    func testDeleteRemovesCredential() throws {
        let store = InMemoryCredentialStore()
        let r = credentialRecipient(normalizedEndpoint: "https://a.example/v1", authType: "bearer")
        try store.save(profileID: "p1", recipient: r, fingerprint: "1111", secret: "SECRET")
        try store.delete(profileID: "p1", recipient: r)
        XCTAssertNil(try store.read(profileID: "p1", recipient: r))
    }

    func testFingerprintOnlyLastFour() throws {
        XCTAssertEqual(credentialFingerprint(secret: "sk-1234567890"), "7890")
        XCTAssertEqual(credentialFingerprint(secret: "ab"), "ab")
    }

    func testKeychainRoundtripIfAvailable() throws {
        #if canImport(Security)
        let store = KeychainCredentialStore()
        let r = credentialRecipient(normalizedEndpoint: "https://keychain-test.example/v1", authType: "bearer")
        do {
            try store.save(profileID: "test", recipient: r, fingerprint: "1234", secret: "MY_SECRET_KEY")
            let entry = try store.read(profileID: "test", recipient: r)
            XCTAssertEqual(entry?.secret, "MY_SECRET_KEY")
            XCTAssertEqual(entry?.fingerprint, "Y_KEY")
            try store.delete(profileID: "test", recipient: r)
            XCTAssertNil(try store.read(profileID: "test", recipient: r))
        } catch {
            throw XCTSkip("Keychain unavailable in this environment: \(error)")
        }
        #else
        throw XCTSkipError("Security framework unavailable")
        #endif
    }

    // MARK: - Consent

    private func permission(
        endpoint: String = "https://a.example/v1",
        model: String = "m",
        authType: String = "bearer",
        scopes: [String: Bool] = ["heart": true],
        version: String = "v1"
    ) -> AIPermission {
        AIPermission(
            profileID: "p1",
            normalizedEndpoint: endpoint,
            model: model,
            authType: authType,
            scopes: scopes,
            scopeVersion: version,
            grantedAt: Date()
        )
    }

    func testEndpointChangeInvalidatesPermission() {
        let old = permission(endpoint: "https://a.example/v1")
        let new = permission(endpoint: "https://b.example/v1")
        XCTAssertFalse(isPermissionValid(old, for: new))
    }

    func testModelChangeInvalidatesPermission() {
        let old = permission(model: "m1")
        let new = permission(model: "m2")
        XCTAssertFalse(isPermissionValid(old, for: new))
    }

    func testAuthTypeChangeInvalidatesPermission() {
        let old = permission(authType: "bearer")
        let new = permission(authType: "x-api-key")
        XCTAssertFalse(isPermissionValid(old, for: new))
    }

    func testScopeVersionChangeInvalidatesPermission() {
        let old = permission(version: "v1")
        let new = permission(version: "v2")
        XCTAssertFalse(isPermissionValid(old, for: new))
    }

    func testNarrowingScopePasses() {
        let old = permission(scopes: ["heart": true, "sleep": true])
        let new = permission(scopes: ["heart": true])
        XCTAssertTrue(isPermissionValid(old, for: new))
    }

    func testExpandingScopeFails() {
        let old = permission(scopes: ["heart": true])
        let new = permission(scopes: ["heart": true, "sleep": true])
        XCTAssertFalse(isPermissionValid(old, for: new))
    }

    func testFactsFilteredByScope() {
        let heart = EvidenceFact(id: "H1", scope: "heart", metric: "hr", value: 60, unit: "bpm", sampleCount: 1, window: TimeWindow(start: Date(), end: Date(), timeZone: tz), sourceRef: "A", synthetic: true)
        let sleep = EvidenceFact(id: "S1", scope: "sleep", metric: "sleep", value: 400, unit: "min", sampleCount: 1, window: TimeWindow(start: Date(), end: Date(), timeZone: tz), sourceRef: "A", synthetic: true)
        let perm = permission(scopes: ["heart": true])
        let filtered = filterFacts([heart, sleep], by: perm)
        XCTAssertEqual(filtered.map(\.id), ["H1"])
    }

    // MARK: - InferenceCache

    private func sampleRecord(evidenceIDs: Set<String> = ["H1"]) -> InferenceRecord {
        InferenceRecord(
            result: AIResult(summary: "s", evidenceIds: Array(evidenceIDs), uncertainties: [], suggestions: [], emotion: nil),
            evidenceIDs: evidenceIDs,
            generation: 1
        )
    }

    private func sampleKey(inputHash: String = "abc", generation: Int = 1) -> InferenceCacheKey {
        let fixedDate = Date(timeIntervalSince1970: 0)
        return InferenceCacheKey(
            task: "mood",
            inputHash: inputHash,
            window: TimeWindow(start: fixedDate, end: fixedDate, timeZone: tz),
            model: "m",
            normalizedEndpoint: "https://a.example/v1",
            promptVersion: "1",
            sourcePolicyVersion: "1",
            consentVersion: "1",
            generation: generation
        )
    }

    func testCacheHitForSameKey() async {
        let cache = InferenceCache()
        let key = sampleKey()
        let record = sampleRecord()
        await cache.put(record, for: key)
        let fetched = await cache.get(key)
        XCTAssertEqual(fetched, record)
    }

    func testCacheMissForDifferentKey() async {
        let cache = InferenceCache()
        await cache.put(sampleRecord(), for: sampleKey(inputHash: "abc"))
        let miss = await cache.get(sampleKey(inputHash: "def"))
        XCTAssertNil(miss)
    }

    func testGenerationBumpInvalidatesOldEntries() async {
        let cache = InferenceCache()
        await cache.put(sampleRecord(), for: sampleKey(generation: 1))
        let miss = await cache.get(sampleKey(generation: 2))
        XCTAssertNil(miss)
    }

    func testInvalidateByEvidenceID() async {
        let cache = InferenceCache()
        let r1 = sampleRecord(evidenceIDs: ["H1", "H2"])
        let r2 = sampleRecord(evidenceIDs: ["H3"])
        let k1 = sampleKey(inputHash: "k1")
        let k2 = sampleKey(inputHash: "k2")
        await cache.put(r1, for: k1)
        await cache.put(r2, for: k2)
        await cache.invalidate(evidenceIDs: ["H1"])
        let miss = await cache.get(k1)
        let kept = await cache.get(k2)
        XCTAssertNil(miss)
        XCTAssertEqual(kept, r2)
    }

    func testConcurrentPutGetSafety() async {
        let cache = InferenceCache()
        let record = sampleRecord()
        let keys = (0..<100).map { sampleKey(inputHash: "\($0)") }
        await withTaskGroup(of: Void.self) { group in
            for key in keys {
                group.addTask {
                    await cache.put(record, for: key)
                }
            }
            for key in keys {
                group.addTask {
                    _ = await cache.get(key)
                }
            }
        }
        let fetched = await cache.get(sampleKey(inputHash: "50"))
        XCTAssertEqual(fetched, record)
    }
}
