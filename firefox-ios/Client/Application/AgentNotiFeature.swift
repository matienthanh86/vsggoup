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
    private var lastHandledCallKey: String = ""
    private var lastHandledCallTime: Date = .distantPast

    public private(set) var pendingOpenUrl: URL?

    public func consumePendingOpenUrl() -> URL? {
        let url = pendingOpenUrl
        pendingOpenUrl = nil
        return url
    }

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
        AgentNotiCallKitManager.shared.reportCallEnded(callKey: callKey, reason: .declinedElsewhere)
        guard let callKey = callKey, !callKey.isEmpty else { return }
        guard let agentId = getSavedAgentId(), let uid = (getSavedUserId() ?? getSavedUsername()) else { return }
        Task {
            _ = try? await apiClient.declineCall(agentId: agentId, uid: uid, callId: callKey, roomToken: callKey)
        }
    }

    public func handleIncomingNotification(userInfo: [AnyHashable: Any]) {
        let dataDict = (userInfo["data"] as? [String: Any]) ?? [:]

        func getString(_ keys: [String]) -> String? {
            for key in keys {
                if let s = userInfo[key] as? String, !s.isEmpty { return s }
                if let n = userInfo[key] as? NSNumber { return n.stringValue }
                if let s = dataDict[key] as? String, !s.isEmpty { return s }
                if let n = dataDict[key] as? NSNumber { return n.stringValue }
            }
            return nil
        }

        let eventType = getString(["eventType", "type"]) ?? "message"
        let callKey = getString(["callId", "roomToken", "room", "objectId"]) ?? ""

        let isCallCancel = ["call_cancel", "call_end", "call_timeout", "end_call"].contains {
            $0.caseInsensitiveCompare(eventType) == .orderedSame
        }

        if isCallCancel {
            AgentNotiCallKitManager.shared.reportCallEnded(callKey: callKey, reason: .remoteEnded)
            AgentNotiAudioPlayer.shared.stopCallRingtone()
            AgentNotiAudioPlayer.shared.playEndCallSound()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("AgentNotiRemoteCallEnded"), object: nil)
                IncomingCallViewController.activeInstance?.dismiss(animated: true)
                self.removeDeliveredCallNotification(callKey: callKey)
            }
            return
        }

        let isCall = eventType.caseInsensitiveCompare("call") == .orderedSame

        if isCall {
            let now = Date()
            if !callKey.isEmpty && callKey == lastHandledCallKey && now.timeIntervalSince(lastHandledCallTime) < 3.0 {
                // Ignore duplicate incoming call notification within 3 seconds
                return
            }
            lastHandledCallKey = callKey
            lastHandledCallTime = now
        }

        let sender = getString(["sender", "callerName"])
        let room = getString(["room"])
        let isGroup = (getString(["isGroup"]) ?? "").lowercased() == "true"

        var title = getString(["title"]) ?? ((userInfo["aps"] as? [String: Any])?["alert"] as? [String: Any])?["title"] as? String
        if title == nil || title?.isEmpty == true {
            if let sender = sender, !sender.isEmpty {
                title = (isGroup && room?.isEmpty == false) ? "\(sender) (\(room!))" : sender
            } else {
                title = "DINO"
            }
        }

        var body = getString(["body", "content"]) ??
            (((userInfo["aps"] as? [String: Any])?["alert"] as? [String: Any])?["body"] as? String) ?? ""
        if isCall && body.isEmpty {
            body = "Cuộc gọi đến..."
        }

        let avatarUrl = getString(["avatar", "avatar_url", "pic"])
        let finalUrl = buildCallUrl(userInfo: userInfo)

        if isCall {
            let timeoutSeconds: TimeInterval = {
                if let tStr = getString(["timeout"]), let t = Double(tStr), t > 0 {
                    return t
                }
                return 45.0 // Mặc định 45s tự ngắt nếu không nghe máy
            }()

            let caller = title ?? "Cuộc gọi đến"

            // Báo CallKit để bung giao diện cuộc gọi toàn màn hình (kể cả khi màn hình tắt hoặc app chạy ngầm)
            // Chỉ fallback sang nhạc chuông / màn hình custom / local notification nếu CallKit thất bại
            AgentNotiCallKitManager.shared.reportIncomingCall(
                callerName: caller,
                callKey: callKey,
                callUrl: finalUrl
            ) { [weak self] success in
                guard !success else { return }

                AgentNotiAudioPlayer.shared.startCallRingtone(timeoutInterval: timeoutSeconds) { [weak self] in
                    AgentNotiCallKitManager.shared.reportCallEnded(callKey: callKey, reason: .unanswered)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name("AgentNotiRemoteCallEnded"), object: nil)
                        IncomingCallViewController.activeInstance?.dismiss(animated: true)
                        self?.removeDeliveredCallNotification(callKey: callKey)
                    }
                    self?.declineCall(callKey: callKey)
                }

                DispatchQueue.main.async {
                    guard let self else { return }
                    let appState = UIApplication.shared.applicationState
                    if appState == .active {
                        self.presentIncomingCallScreen(
                            caller: caller,
                            callUrl: finalUrl,
                            callKey: callKey,
                            avatarUrl: avatarUrl,
                            timeoutSeconds: timeoutSeconds
                        )
                    } else {
                        self.showCallNotification(
                            title: caller,
                            body: body,
                            url: finalUrl,
                            callKey: callKey
                        )
                    }
                }
            }
        } else {
            showLocalNotification(title: title ?? "DINO", body: body, url: finalUrl)
        }
    }

    public func buildCallUrl(userInfo: [AnyHashable: Any]) -> String {
        let dataDict = (userInfo["data"] as? [String: Any]) ?? [:]

        func getString(_ keys: [String]) -> String? {
            for key in keys {
                if let s = userInfo[key] as? String, !s.isEmpty { return s }
                if let n = userInfo[key] as? NSNumber { return n.stringValue }
                if let s = dataDict[key] as? String, !s.isEmpty { return s }
                if let n = dataDict[key] as? NSNumber { return n.stringValue }
            }
            return nil
        }

        let eventType = getString(["eventType", "type"]) ?? "message"
        let callKey = getString(["callId", "roomToken", "room", "objectId"]) ?? ""
        let room = getString(["room"])
        var base = getSavedBaseWebUrl()
        while base.hasSuffix("/") {
            base.removeLast()
        }
        let tokenRoom = !callKey.isEmpty ? callKey : (room ?? "")

        if eventType.caseInsensitiveCompare("call") == .orderedSame {
            return "\(base)?path=call/\(tokenRoom)&param=callNoti"
        } else if eventType.caseInsensitiveCompare("message") == .orderedSame && !tokenRoom.isEmpty {
            return "\(base)?path=call/\(tokenRoom)&param=messageNoti"
        } else {
            return getString(["targetUrl", "url", "openUrl"]) ?? base
        }
    }

    public func removeDeliveredCallNotification(callKey: String) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let matchingIds = notifications.filter { notification in
                let userInfo = notification.request.content.userInfo
                let dataDict = userInfo["data"] as? [String: Any]
                let key = (userInfo["callId"] as? String) ??
                    (userInfo["roomToken"] as? String) ??
                    (userInfo["room"] as? String) ??
                    (userInfo["objectId"] as? String) ??
                    (dataDict?["callId"] as? String) ??
                    (dataDict?["roomToken"] as? String) ??
                    (dataDict?["room"] as? String) ??
                    (dataDict?["objectId"] as? String) ?? ""
                return (!callKey.isEmpty && (key == callKey || notification.request.identifier.contains(callKey))) ||
                       (notification.request.content.categoryIdentifier == DinoCallNotificationCategory.categoryIdentifier)
            }.map { $0.request.identifier }

            if !matchingIds.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: matchingIds)
            }
        }
        center.getPendingNotificationRequests { requests in
            let matchingPending = requests.filter { req in
                let userInfo = req.content.userInfo
                let key = (userInfo["callId"] as? String) ??
                    (userInfo["roomToken"] as? String) ?? ""
                return (!callKey.isEmpty && (key == callKey || req.identifier.contains(callKey))) ||
                       (req.content.categoryIdentifier == DinoCallNotificationCategory.categoryIdentifier)
            }.map { $0.identifier }

            if !matchingPending.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: matchingPending)
            }
        }
    }

    @MainActor
    private func presentIncomingCallScreen(
        caller: String,
        callUrl: String,
        callKey: String,
        avatarUrl: String? = nil,
        timeoutSeconds: TimeInterval = 45.0
    ) {
        if IncomingCallViewController.activeInstance != nil {
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            if presented is IncomingCallViewController || presented.isBeingPresented || presented.isBeingDismissed {
                return
            }
            topVC = presented
        }
        if topVC is IncomingCallViewController {
            return
        }

        let callVC = IncomingCallViewController()
        callVC.modalPresentationStyle = .fullScreen
        callVC.callerName = caller
        callVC.callUrl = callUrl
        callVC.callKey = callKey
        callVC.avatarUrl = avatarUrl
        callVC.timeoutInterval = timeoutSeconds
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
        self.pendingOpenUrl = url
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("AgentNotiOpenURLInBrowser"),
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    private func showCallNotification(title: String, body: String, url: String, callKey: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body.isEmpty ? "Cuộc gọi đến..." : body
        content.categoryIdentifier = DinoCallNotificationCategory.categoryIdentifier
        content.sound = .default
        content.userInfo = [
            "eventType": "call",
            "callId": callKey,
            "roomToken": callKey,
            "targetUrl": url
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let identifier = !callKey.isEmpty ? "dino_call_\(callKey)" : UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
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
              host.contains("dino.top") else {
            return
        }
        let scheme = url.scheme ?? "https"
        let base = "\(scheme)://\(host)"
        prefs.set(base, forKey: keyBaseWebUrl)
    }
}
