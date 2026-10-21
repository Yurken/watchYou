import Foundation

/// Recorded user permission for a specific AI destination.
public struct AIPermission: Equatable, Sendable, Codable {
    public let profileID: String
    public let normalizedEndpoint: String
    public let model: String
    public let authType: String
    public let scopes: [String: Bool]
    public let scopeVersion: String
    public let grantedAt: Date

    public init(
        profileID: String,
        normalizedEndpoint: String,
        model: String,
        authType: String,
        scopes: [String: Bool],
        scopeVersion: String,
        grantedAt: Date
    ) {
        self.profileID = profileID
        self.normalizedEndpoint = normalizedEndpoint
        self.model = model
        self.authType = authType
        self.scopes = scopes
        self.scopeVersion = scopeVersion
        self.grantedAt = grantedAt
    }
}

/// Check whether an existing permission is still valid for the requested configuration.
public func isPermissionValid(_ permission: AIPermission, for request: AIPermission) -> Bool {
    guard permission.normalizedEndpoint == request.normalizedEndpoint,
          permission.model == request.model,
          permission.authType == request.authType,
          permission.scopeVersion == request.scopeVersion else {
        return false
    }

    // Any scope that is now requested as true but was not granted invalidates the permission.
    for (key, requested) in request.scopes where requested == true {
        if permission.scopes[key] != true { return false }
    }

    return true
}

/// Filter facts to include only scopes currently allowed by the permission.
public func filterFacts(_ facts: [EvidenceFact], by permission: AIPermission) -> [EvidenceFact] {
    facts.filter { fact in
        guard let scope = fact.scope else { return true }
        return permission.scopes[scope] == true
    }
}
