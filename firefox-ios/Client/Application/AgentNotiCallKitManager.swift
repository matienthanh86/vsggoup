// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import CallKit
import AVFoundation
import UIKit

public final class AgentNotiCallKitManager: NSObject, CXProviderDelegate, @unchecked Sendable {
    public static let shared = AgentNotiCallKitManager()

    private var provider: CXProvider?
    public let callController = CXCallController()

    public private(set) var currentCallUUID: UUID?
    public private(set) var currentCallKey: String?
    public private(set) var currentCallUrl: String?
    public private(set) var currentCallerName: String?

    private override init() {
        super.init()
        setupProvider()
    }

    private func setupProvider() {
        let configuration = CXProviderConfiguration(localizedName: "VSG Group")
        configuration.supportsVideo = true
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportedHandleTypes = [.generic, .phoneNumber]
        configuration.ringtoneSound = "universfield_incoming_phone_call_152490.mp3"
        configuration.includesCallsInRecents = false

        let provider = CXProvider(configuration: configuration)
        provider.setDelegate(self, queue: .main)
        self.provider = provider
    }

    /// Báo cho hệ thống iOS có cuộc gọi đến để bung toàn màn hình (kể cả khi tắt màn hình hoặc chạy ngầm)
    public func reportIncomingCall(
        callerName: String,
        callKey: String,
        callUrl: String,
        hasVideo: Bool = false,
        completion: (@Sendable (Bool) -> Void)? = nil
    ) {
        let uuid: UUID = {
            if !callKey.isEmpty, let u = UUID(uuidString: callKey) {
                return u
            }
            return UUID()
        }()

        self.currentCallUUID = uuid
        self.currentCallKey = callKey
        self.currentCallUrl = callUrl
        self.currentCallerName = callerName

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.localizedCallerName = callerName
        update.hasVideo = hasVideo
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        guard let provider = self.provider else {
            completion?(false)
            return
        }

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error = error {
                print("[CallKit] Error reporting new incoming call: \(error.localizedDescription)")
                self?.currentCallUUID = nil
                self?.currentCallKey = nil
                self?.currentCallUrl = nil
                self?.currentCallerName = nil
                completion?(false)
            } else {
                print("[CallKit] Successfully reported incoming call for \(callerName)")
                completion?(true)
            }
        }
    }

    /// Báo cho iOS ngắt cuộc gọi khi bên kia dập máy (call_cancel / call_end / timeout)
    public func reportCallEnded(callKey: String? = nil, reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = currentCallUUID else { return }
        if let key = callKey, !key.isEmpty, let currKey = currentCallKey, key != currKey {
            return
        }

        provider?.reportCall(with: uuid, endedAt: Date(), reason: reason)
        currentCallUUID = nil
        currentCallKey = nil
        currentCallUrl = nil
        currentCallerName = nil
    }

    // MARK: - CXProviderDelegate

    public func providerDidReset(_ provider: CXProvider) {
        currentCallUUID = nil
        currentCallKey = nil
        currentCallUrl = nil
        currentCallerName = nil
        AgentNotiAudioPlayer.shared.stopCallRingtone()
    }

    /// Người dùng trượt / bấm "Nghe" (Accept) trên màn hình khóa hoặc giao diện CallKit
    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        action.fulfill()

        AgentNotiAudioPlayer.shared.stopCallRingtone()

        let targetUrl = currentCallUrl ?? ""
        let key = currentCallKey ?? ""

        if !key.isEmpty {
            AgentNotiFeature.shared.removeDeliveredCallNotification(callKey: key)
        }

        // Tắt màn hình cuộc gọi custom nếu đang hiện
        IncomingCallViewController.activeInstance?.dismiss(animated: false)

        // Mở browser và focus vào tab cuộc gọi dino.top
        if !targetUrl.isEmpty {
            AgentNotiFeature.shared.openUrlInBrowser(targetUrl)
        }

        // Sau khi chuyển vào browser thành công, kết thúc CallKit để nhường quyền Audio/Video hoàn toàn cho WKWebView
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if let uuid = self?.currentCallUUID {
                self?.provider?.reportCall(with: uuid, endedAt: Date(), reason: .answeredElsewhere)
                self?.currentCallUUID = nil
                self?.currentCallKey = nil
                self?.currentCallUrl = nil
                self?.currentCallerName = nil
            }
        }
    }

    /// Người dùng bấm "Từ chối" (Decline) trên màn hình khóa hoặc giao diện CallKit
    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()

        AgentNotiAudioPlayer.shared.stopCallRingtone()
        AgentNotiAudioPlayer.shared.playEndCallSound()

        let key = currentCallKey ?? ""
        if !key.isEmpty {
            AgentNotiFeature.shared.removeDeliveredCallNotification(callKey: key)
            AgentNotiFeature.shared.declineCall(callKey: key)
        }

        IncomingCallViewController.activeInstance?.dismiss(animated: false)

        currentCallUUID = nil
        currentCallKey = nil
        currentCallUrl = nil
        currentCallerName = nil
    }

    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        try? audioSession.setActive(true)
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
