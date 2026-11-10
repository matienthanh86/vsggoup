// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit
import Common

public final class AgentNotiApiClient: @unchecked Sendable {
    public static let defaultBaseUrl = "https://agent-dev-api.dino.top"
    public static let defaultDinoAuthUrl = "https://api-dev.dino.top"

    public let baseUrl: String
    public let dinoAuthUrl: String

    public init(baseUrl: String = defaultBaseUrl, dinoAuthUrl: String = defaultDinoAuthUrl) {
        self.baseUrl = baseUrl
        self.dinoAuthUrl = dinoAuthUrl
    }

    public func registerDevice(savedAgentId: String? = nil, platform: String = "ios") async throws -> String {
        let (deviceName, deviceType) = await MainActor.run {
            (UIDevice.current.name, UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone")
        }
        let appVersion = AppInfo.appVersion

        var body: [String: Any] = [
            "deviceName": deviceName,
            "platform": platform,
            "deviceType": deviceType,
            "appVersion": appVersion
        ]
        if let savedAgentId = savedAgentId, !savedAgentId.isEmpty {
            body["agentId"] = savedAgentId
        }

        let response = try await postAgentApi(path: "/api/devices/register", jsonBody: body)
        guard let json = response as? [String: Any] else {
            throw NSError(domain: "AgentNoti", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
        }

        let agentId = (json["agentId"] as? String) ??
            (json["AgentId"] as? String) ??
            (json["id"] as? String)

        guard let id = agentId, !id.isEmpty else {
            throw NSError(domain: "AgentNoti", code: -1, userInfo: [NSLocalizedDescriptionKey: "No agentId in response"])
        }
        return id
    }

    public func registerPushToken(
        agentId: String,
        pushAddress: String,
        provider: String = "apns",
        tokenType: String = "standard"
    ) async throws -> Bool {
        let body: [String: Any] = [
            "agentId": agentId,
            "provider": provider,
            "pushAddress": pushAddress,
            "tokenType": tokenType
        ]
        _ = try await postAgentApi(path: "/api/push-tokens", jsonBody: body)
        return true
    }

    public func exchangeDinoTicket(ticket: String) async throws -> [String: Any] {
        let body: [String: Any] = ["ticket": ticket]
        let headers: [String: String] = [
            "client-id": "1",
            "device": "iOS",
            "x-access-type": "Internal"
        ]
        let url = "\(dinoAuthUrl)/dino-platform/v3/auth/exchange-ticket"
        let response = try await postJson(urlString: url, jsonBody: body, headers: headers, timeout: 10.0)
        guard let json = response as? [String: Any] else {
            throw NSError(domain: "AgentNoti", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid dino ticket response"])
        }
        return json
    }

    public func loginAgent(agentId: String, token: String, appId: String = "dino") async throws -> [String: Any] {
        let body: [String: Any] = [
            "agentId": agentId,
            "appId": appId,
            "token": token
        ]
        let response = try await postAgentApi(path: "/api/auth/login", jsonBody: body)
        guard let json = response as? [String: Any] else {
            throw NSError(domain: "AgentNoti", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid login response"])
        }
        return json
    }

    public func exchangeTicket(agentId: String, ticket: String) async throws -> [String: Any] {
        let body: [String: Any] = [
            "agentId": agentId,
            "ticket": ticket
        ]
        let response = try await postAgentApi(path: "/api/auth/ticket/exchange", jsonBody: body)
        guard let json = response as? [String: Any] else {
            throw NSError(domain: "AgentNoti", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid ticket response"])
        }
        return json
    }

    public func logoutApp(agentId: String, appId: String = "dino") async throws -> Bool {
        let body: [String: Any] = [
            "agentId": agentId,
            "appId": appId
        ]
        _ = try await postAgentApi(path: "/api/auth/logout", jsonBody: body)
        return true
    }

    public func acceptCall(agentId: String, uid: String, callId: String) async throws -> Bool {
        let body: [String: Any] = [
            "agentId": agentId,
            "uid": uid,
            "callId": callId
        ]
        _ = try await postAgentApi(path: "/api/calls/accept", jsonBody: body)
        return true
    }

    public func declineCall(
        agentId: String,
        uid: String,
        callId: String,
        roomToken: String? = nil
    ) async throws -> Bool {
        var body: [String: Any] = [
            "agentId": agentId,
            "uid": uid,
            "callId": callId
        ]
        if let roomToken = roomToken, !roomToken.isEmpty {
            body["roomToken"] = roomToken
        }
        _ = try await postAgentApi(path: "/api/calls/decline", jsonBody: body)
        return true
    }

    private func postAgentApi(path: String, jsonBody: [String: Any]) async throws -> Any {
        let fullUrl = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
        return try await postJson(urlString: fullUrl, jsonBody: jsonBody, headers: [:], timeout: 20.0)
    }

    private func postJson(
        urlString: String,
        jsonBody: [String: Any],
        headers: [String: String],
        timeout: TimeInterval
    ) async throws -> Any {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "AgentNoti", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL \(urlString)"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) VSG-AgentNoti/1.0", forHTTPHeaderField: "User-Agent")

        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AgentNoti", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not a valid HTTP response"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseString = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "AgentNoti",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(responseString)"]
            )
        }

        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
