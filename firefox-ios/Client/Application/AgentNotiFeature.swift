// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit
import UserNotifications
import Common

public final class AgentNotiFeature: @unchecked Sendable {
    public static let shared = AgentNotiFeature()

    public let apiClient: AgentNotiApiClient

    private let prefs = UserDefaults.standard
    private let keyAgentId = "vsg_agent_id"
    private let keyApnsToken = "vsg_apns_token"
    private let keyUserId = "vsg_user_id"
    private let keyUsername = "vsg_username"
    private let keyDisplayName = "vsg_display_name"
    private let keySessionId = "vsg_session_id"
    private let keyAuthToken = "vsg_auth_token"
    private let keyBaseWebUrl = "vsg_base_web_url"

    private let retryDelays: [UInt64] = [0, 2, 5, 15, 30, 60]
    private var isConnecting = false
    private var lastConnectAttemptTime: TimeInterval = 0
    private var lastAttemptedTicket: String?

    public init(apiClient: AgentNotiApiClient? = nil) {
        self.apiClient = apiClient ?? AgentNotiApiClient()
    }

    public func start() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            UIApplication.shared.registerForRemoteNotifications()
        }

        Task {
            await initAndSyncPushToken()
        }
    }

    private func initAndSyncPushToken() async {
        let savedAgentId = getSavedAgentId()
        let agentId = await retryOperation(name: "device registration") {
            try await self.apiClient.registerDevice(savedAgentId: savedAgentId)
        }

        if let id = agentId {
            saveAgentId(id)
            if let token = getSavedApnsToken() {
                _ = await retryOperation(name: "APNs token registration") {
                    try await self.apiClient.registerPushToken(agentId: id, pushAddress: token, provider: "apns")
                }
            }
        }
    }

    public func handleNewToken(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        saveApnsToken(token)

        Task {
            var agentId = getSavedAgentId()
            if agentId == nil {
                agentId = try? await apiClient.registerDevice()
            }
            guard let finalAgentId = agentId else {
                return
            }
            saveAgentId(finalAgentId)
            _ = try? await apiClient.registerPushToken(agentId: finalAgentId, pushAddress: token, provider: "apns")
        }
    }

    public func connectViaTicket(ticket: String, completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil) {
        let savedToken = getSavedAuthToken()
        if savedToken == ticket && isLoggedIn() {
            let username = getSavedUsername()
            Task { @MainActor in completion?(true, username) }
            return
        }

        let now = Date().timeIntervalSince1970
        if isConnecting || (ticket == lastAttemptedTicket && now - lastConnectAttemptTime < 10) {
            return
        }
        isConnecting = true
        lastConnectAttemptTime = now
        lastAttemptedTicket = ticket

        Task {
            defer { isConnecting = false }
            do {
                var agentId = getSavedAgentId()
                if agentId == nil {
                    agentId = try await apiClient.registerDevice()
                    if let newId = agentId {
                        saveAgentId(newId)
                    }
                }

                guard let validAgentId = agentId else {
                    Task { @MainActor in completion?(false, "Device registration failed") }
                    return
                }

                if ticket.hasPrefix("eyJ") {
                    if let loginJson = try? await apiClient.loginAgent(agentId: validAgentId, token: ticket) {
                        let userObj = (loginJson["user"] as? [String: Any]) ?? loginJson
                        let uid = (userObj["uid"] as? String) ?? (loginJson["uid"] as? String) ?? ""
                        let un = (userObj["username"] as? String) ?? "DINO User"
                        let dn = (userObj["displayName"] as? String) ?? un
                        let sid = (loginJson["sessionId"] as? String) ?? ""

                        saveUserSession(userId: uid, username: un, displayName: dn, sessionId: sid)
                        saveAuthToken(ticket)

                        Task { @MainActor in
                            self.showToast("Đã kết nối tài khoản DINO: \(un)")
                            completion?(true, un)
                        }
                        syncApnsTokenWithBackend(agentId: validAgentId)
                        return
                    }
                }

                if let agentNotiResult = try? await apiClient.exchangeTicket(agentId: validAgentId, ticket: ticket) {
                    let user = (agentNotiResult["user"] as? [String: Any]) ?? agentNotiResult
                    let uid = (user["uid"] as? String) ?? (agentNotiResult["uid"] as? String) ?? ""
                    let username = (user["username"] as? String) ?? "DINO User"
                    let dn = (user["displayName"] as? String) ?? username
                    let sid = (agentNotiResult["sessionId"] as? String) ?? ""

                    saveUserSession(userId: uid, username: username, displayName: dn, sessionId: sid)
                    saveAuthToken(ticket)

                    Task { @MainActor in
                        self.showToast("Đã kết nối tài khoản DINO: \(username)")
                        completion?(true, username)
                    }
                    syncApnsTokenWithBackend(agentId: validAgentId)
                    return
                }

                if let dinoResult = try? await apiClient.exchangeDinoTicket(ticket: ticket) {
                    let data = (dinoResult["data"] as? [String: Any]) ?? dinoResult
                    let tokenToBind = (data["token"] as? String) ??
                        (data["accessToken"] as? String) ??
                        (data["jwt"] as? String)

                    let user = data["user"] as? [String: Any]
                    let resolvedUsername = (user?["username"] as? String) ??
                        (user?["userName"] as? String) ??
                        (data["username"] as? String) ??
                        "DINO User"

                    if let token = tokenToBind, !token.isEmpty {
                        if let loginJson = try? await apiClient.loginAgent(agentId: validAgentId, token: token) {
                            let userObj = (loginJson["user"] as? [String: Any]) ?? loginJson
                            let uid = (userObj["uid"] as? String) ?? (loginJson["uid"] as? String) ?? ""
                            let un = (userObj["username"] as? String) ?? resolvedUsername
                            let dn = (userObj["displayName"] as? String) ?? un
                            let sid = (loginJson["sessionId"] as? String) ?? ""

                            saveUserSession(userId: uid, username: un, displayName: dn, sessionId: sid)
                            saveAuthToken(ticket)

                            Task { @MainActor in
                                self.showToast("Đã kết nối tài khoản DINO: \(un)")
                                completion?(true, un)
                            }
                            syncApnsTokenWithBackend(agentId: validAgentId)
                            return
                        }
                    }
                }

                Task { @MainActor in completion?(false, "Ticket exchange failed") }
            } catch {
                Task { @MainActor in completion?(false, error.localizedDescription) }
            }
        }
    }

    private func syncApnsTokenWithBackend(agentId: String) {
        guard let token = getSavedApnsToken(), !token.isEmpty else { return }
        Task {
            _ = await retryOperation(name: "sync APNs token") {
                try await self.apiClient.registerPushToken(agentId: agentId, pushAddress: token, provider: "apns")
            }
        }
    }

    public func logout(appId: String = "dino", completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil) {
        lastAttemptedTicket = nil
        lastConnectAttemptTime = 0
        let agentId = getSavedAgentId()
        clearUserSession()

        Task { @MainActor in
            self.showToast("Đã đăng xuất tài khoản DINO")
        }

        guard let id = agentId, !id.isEmpty else {
            Task { @MainActor in completion?(true, nil) }
            return
        }

        Task {
            do {
                _ = try await apiClient.logoutApp(agentId: id, appId: appId)
                Task { @MainActor in completion?(true, nil) }
            } catch {
                Task { @MainActor in completion?(false, error.localizedDescription) }
            }
        }
    }

    public func declineCall(callKey: String?) {
        guard let callKey = callKey, !callKey.isEmpty else { return }
        guard let agentId = getSavedAgentId(), let uid = getSavedUserId() else { return }
        Task {
            _ = try? await apiClient.declineCall(agentId: agentId, uid: uid, callId: callKey, roomToken: callKey)
        }
    }

    public func handleIncomingNotification(userInfo: [AnyHashable: Any]) {
        let eventType = (userInfo["eventType"] as? String) ?? (userInfo["type"] as? String) ?? "message"
        let callKey = (userInfo["callId"] as? String) ??
            (userInfo["roomToken"] as? String) ??
            (userInfo["room"] as? String) ??
            (userInfo["objectId"] as? String) ?? ""

        let isCallCancel = ["call_cancel", "call_end", "call_timeout", "end_call"].contains {
            $0.caseInsensitiveCompare(eventType) == .orderedSame
        }

        if isCallCancel {
            AgentNotiAudioPlayer.shared.playEndCallSound()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("AgentNotiRemoteCallEnded"), object: nil)
                IncomingCallViewController.activeInstance?.dismiss(animated: true)
            }
            return
        }

        let isCall = eventType.caseInsensitiveCompare("call") == .orderedSame
        let sender = (userInfo["sender"] as? String) ?? (userInfo["callerName"] as? String)
        let room = userInfo["room"] as? String
        let isGroup = (userInfo["isGroup"] as? String)?.lowercased() == "true"

        var title = (userInfo["title"] as? String) ?? ((userInfo["aps"] as? [String: Any])?["alert"] as? [String: Any])?["title"] as? String
        if title == nil || title?.isEmpty == true {
            if let sender = sender, !sender.isEmpty {
                title = (isGroup && room?.isEmpty == false) ? "\(sender) (\(room!))" : sender
            } else {
                title = "DINO"
            }
        }

        var body = (userInfo["body"] as? String) ??
            (userInfo["content"] as? String) ??
            (((userInfo["aps"] as? [String: Any])?["alert"] as? [String: Any])?["body"] as? String) ?? ""
        if isCall && body.isEmpty {
            body = "Cuộc gọi đến..."
        }

        let defaultBase = getSavedBaseWebUrl()
        let url = (userInfo["targetUrl"] as? String) ??
            (userInfo["url"] as? String) ??
            (userInfo["openUrl"] as? String) ??
            defaultBase

        if isCall {
            AgentNotiAudioPlayer.shared.startCallRingtone()
            DispatchQueue.main.async {
                self.presentIncomingCallScreen(caller: title ?? "Cuộc gọi đến", callUrl: url, callKey: callKey)
            }
        } else {
            showLocalNotification(title: title ?? "DINO", body: body, url: url)
        }
    }

    public func triggerTestNotification(isCall: Bool = false) {
        if isCall {
            let mockCallPayload: [AnyHashable: Any] = [
                "eventType": "call",
                "callId": "test_call_\(Int(Date().timeIntervalSince1970))",
                "callerName": "DINO Support",
                "title": "Cuộc gọi từ DINO Support",
                "body": "Cuộc gọi đến từ hệ thống...",
                "targetUrl": "https://dev.dino.top"
            ]
            handleIncomingNotification(userInfo: mockCallPayload)
        } else {
            let mockMessagePayload: [AnyHashable: Any] = [
                "eventType": "message",
                "title": "DINO Platform",
                "body": "Xin chào! Bạn có 1 thông báo mới từ hệ thống VSG Group.",
                "targetUrl": "https://dev.dino.top"
            ]
            handleIncomingNotification(userInfo: mockMessagePayload)
        }
    }

    @MainActor
    private func presentIncomingCallScreen(caller: String, callUrl: String, callKey: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let callVC = IncomingCallViewController()
        callVC.modalPresentationStyle = .fullScreen
        callVC.callerName = caller
        callVC.callUrl = callUrl
        callVC.callKey = callKey
        callVC.onCallAccepted = { [weak self] targetUrl in
            self?.openUrlInBrowser(targetUrl)
        }
        callVC.onCallDeclined = { [weak self] key in
            self?.declineCall(callKey: key)
        }
        topVC.present(callVC, animated: true)
    }

    public func openUrlInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NotificationCenter.default.post(
            name: NSNotification.Name("AgentNotiOpenURLInBrowser"),
            object: nil,
            userInfo: ["url": url]
        )
    }

    private func showLocalNotification(title: String, body: String, url: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["targetUrl": url]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    @MainActor
    public func showToast(_ message: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return
        }

        let toastContainer = UIView()
        toastContainer.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        toastContainer.layer.cornerRadius = 20
        toastContainer.clipsToBounds = true
        toastContainer.translatesAutoresizingMaskIntoConstraints = false

        let toastLabel = UILabel()
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        toastLabel.text = message
        toastLabel.numberOfLines = 0
        toastLabel.translatesAutoresizingMaskIntoConstraints = false

        toastContainer.addSubview(toastLabel)
        keyWindow.addSubview(toastContainer)

        NSLayoutConstraint.activate([
            toastContainer.bottomAnchor.constraint(equalTo: keyWindow.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            toastContainer.centerXAnchor.constraint(equalTo: keyWindow.centerXAnchor),
            toastContainer.leadingAnchor.constraint(greaterThanOrEqualTo: keyWindow.leadingAnchor, constant: 24),
            toastContainer.trailingAnchor.constraint(lessThanOrEqualTo: keyWindow.trailingAnchor, constant: -24),

            toastLabel.topAnchor.constraint(equalTo: toastContainer.topAnchor, constant: 10),
            toastLabel.bottomAnchor.constraint(equalTo: toastContainer.bottomAnchor, constant: -10),
            toastLabel.leadingAnchor.constraint(equalTo: toastContainer.leadingAnchor, constant: 18),
            toastLabel.trailingAnchor.constraint(equalTo: toastContainer.trailingAnchor, constant: -18)
        ])

        toastContainer.alpha = 0
        UIView.animate(withDuration: 0.3) {
            toastContainer.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.5, options: []) {
                toastContainer.alpha = 0
            } completion: { _ in
                toastContainer.removeFromSuperview()
            }
        }
    }

    private func retryOperation<T>(name: String, operation: () async throws -> T) async -> T? {
        for (index, delaySec) in retryDelays.enumerated() {
            if delaySec > 0 {
                try? await Task.sleep(nanoseconds: delaySec * 1_000_000_000)
            }
            do {
                return try await operation()
            } catch {
                if index == retryDelays.count - 1 {
                    return nil
                }
            }
        }
        return nil
    }

    public func getSavedAgentId() -> String? { prefs.string(forKey: keyAgentId) }
    public func saveAgentId(_ agentId: String) { prefs.set(agentId, forKey: keyAgentId) }

    public func getSavedApnsToken() -> String? { prefs.string(forKey: keyApnsToken) }
    public func saveApnsToken(_ token: String) { prefs.set(token, forKey: keyApnsToken) }

    public func getSavedUserId() -> String? { prefs.string(forKey: keyUserId) }
    public func getSavedUsername() -> String? { prefs.string(forKey: keyUsername) }
    public func getSavedDisplayName() -> String? { prefs.string(forKey: keyDisplayName) }
    public func getSavedSessionId() -> String? { prefs.string(forKey: keySessionId) }
    public func getSavedAuthToken() -> String? { prefs.string(forKey: keyAuthToken) }
    public func saveAuthToken(_ token: String) { prefs.set(token, forKey: keyAuthToken) }

    public func saveUserSession(userId: String?, username: String?, displayName: String?, sessionId: String?) {
        prefs.set(userId, forKey: keyUserId)
        prefs.set(username, forKey: keyUsername)
        prefs.set(displayName, forKey: keyDisplayName)
        prefs.set(sessionId, forKey: keySessionId)
    }

    public func clearUserSession() {
        prefs.removeObject(forKey: keyUserId)
        prefs.removeObject(forKey: keyUsername)
        prefs.removeObject(forKey: keyDisplayName)
        prefs.removeObject(forKey: keySessionId)
        prefs.removeObject(forKey: keyAuthToken)
    }

    public func isLoggedIn() -> Bool {
        let uid = getSavedUserId()
        let un = getSavedUsername()
        return (uid != nil && !uid!.isEmpty) || (un != nil && !un!.isEmpty)
    }

    public func getSavedBaseWebUrl() -> String {
        return prefs.string(forKey: keyBaseWebUrl) ?? "https://dev.dino.top"
    }

    public func saveBaseWebUrl(_ urlString: String) {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased(),
              host.contains("dino.top") || host.contains("vietravel") else {
            return
        }
        let scheme = url.scheme ?? "https"
        let base = "\(scheme)://\(host)"
        prefs.set(base, forKey: keyBaseWebUrl)
    }
}
