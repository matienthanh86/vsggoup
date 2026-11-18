// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Shared
import UserNotifications

import class Account.Autopush
import class Account.RustFirefoxAccounts
import struct MozillaAppServices.ConstellationState

/**
 * This exists because the Sync code is extension-safe, and thus doesn't get
 * direct access to UIApplication.sharedApplication, which it would need to display a notification.
 * This will also likely be the extension point for wipes, resets, and getting access to data sources during a sync.
 */
enum SentTabAction: String {
    case view = "TabSendViewAction"

    static var notificationCategory: UNNotificationCategory {
        let viewAction = UNNotificationAction(identifier: SentTabAction.view.rawValue,
                                              title: .SentTabViewActionTitle,
                                              options: .foreground)

        // Register ourselves to handle the notification category set by NotificationService for APNS notifications
        return UNNotificationCategory(
            identifier: "org.mozilla.ios.SentTab.placeholder",
            actions: [viewAction],
            intentIdentifiers: [],
            options: UNNotificationCategoryOptions(rawValue: 0))
    }
}

enum DinoCallNotificationCategory {
    static let categoryIdentifier = "DINO_INCOMING_CALL"
    static let acceptActionIdentifier = "ACCEPT_CALL_ACTION"
    static let declineActionIdentifier = "DECLINE_CALL_ACTION"

    static var notificationCategory: UNNotificationCategory {
        let acceptAction = UNNotificationAction(
            identifier: acceptActionIdentifier,
            title: "Nghe",
            options: [.foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: declineActionIdentifier,
            title: "Từ chối",
            options: [.destructive]
        )
        return UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [acceptAction, declineAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
    }
}

extension AppDelegate {
    func pushNotificationSetup() {
        UNUserNotificationCenter.current().delegate = self
        let categories: Set<UNNotificationCategory> = [
            SentTabAction.notificationCategory,
            NotificationSurfaceManager.notificationCategory,
            DinoCallNotificationCategory.notificationCategory
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)

        NotificationCenter.default.addObserver(forName: .RegisterForPushNotifications, object: nil, queue: .main) { _ in
            Task { @MainActor in
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                if settings.authorizationStatus != .denied {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        // If we see our local device with a pushEndpointExpired flag, try to re-register.
        NotificationCenter.default.addObserver(
            forName: .constellationStateUpdate,
            object: nil,
            queue: .main
        ) { [profile] notification in
            guard let newState = notification.userInfo?["newState"] as? ConstellationState else { return }
            let remoteDevicesCount = newState.remoteDevices.count
            self.setPreferencesForSyncedAccount(for: profile, count: remoteDevicesCount)
            if newState.localDevice?.pushEndpointExpired ?? false {
                NotificationCenter.default.post(name: .RegisterForPushNotifications, object: nil)
                // Our endpoint expired, we should check for missed messages
                profile.pollCommands(forcePoll: true)
            }
        }
    }

    nonisolated private func setPreferencesForSyncedAccount(for profile: Profile, count: Int) {
        guard profile.hasSyncableAccount() else { return }
        profile.prefs.setBool(true, forKey: PrefsKeys.Sync.signedInFxaAccount)
        // The additional +1 is to also add a count for the local device being used
        let devicesCount = Int32(count + 1)
        profile.prefs.setInt(devicesCount, forKey: PrefsKeys.Sync.numberOfSyncedDevices)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Called when the user taps on a notification while in background.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let content = response.notification.request.content

        if content.categoryIdentifier == DinoCallNotificationCategory.categoryIdentifier ||
            (content.userInfo["eventType"] as? String)?.lowercased() == "call" ||
            content.userInfo["callId"] != nil ||
            content.userInfo["roomToken"] != nil {

            let callKey = (content.userInfo["callId"] as? String) ??
                (content.userInfo["roomToken"] as? String) ??
                (content.userInfo["room"] as? String) ?? ""

            AgentNotiAudioPlayer.shared.stopCallRingtone()
            AgentNotiFeature.shared.removeDeliveredCallNotification(callKey: callKey)

            switch response.actionIdentifier {
            case DinoCallNotificationCategory.acceptActionIdentifier, UNNotificationDefaultActionIdentifier:
                let targetUrl = AgentNotiFeature.shared.buildCallUrl(userInfo: content.userInfo)
                AgentNotiFeature.shared.openUrlInBrowser(targetUrl)
            case DinoCallNotificationCategory.declineActionIdentifier, UNNotificationDismissActionIdentifier:
                AgentNotiFeature.shared.declineCall(callKey: callKey)
            default:
                break
            }
            return
        }

        if content.categoryIdentifier == NotificationSurfaceManager.Constant.notificationCategoryId {
            guard let messageId = content.userInfo[NotificationSurfaceManager.Constant.messageIdKey] as? String
            else { return }

            switch response.actionIdentifier {
            case UNNotificationDismissActionIdentifier:
                notificationSurfaceManager.didDismissNotification(messageId)
            default:
                notificationSurfaceManager.didTapNotification(messageId)
            }
        } else if let targetUrl = (content.userInfo["targetUrl"] as? String) ?? (content.userInfo["url"] as? String) {
            AgentNotiFeature.shared.openUrlInBrowser(targetUrl)
        } else if content.categoryIdentifier == NotificationCloseTabs.notificationCategoryId {
            switch response.actionIdentifier {
            case UNNotificationDefaultActionIdentifier:
                // Since the notification is coming from the background, we should give a little
                // time to ensure we can show the recently closed tabs panel
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .RemoteTabNotificationTapped, object: nil)
                }
            default:
                break
            }
        }
    }

    // Called when the user receives a tab (or any other notification) while in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.content.userInfo["eventType"] != nil ||
            notification.request.content.userInfo["callId"] != nil ||
            notification.request.content.userInfo["roomToken"] != nil {
            AgentNotiFeature.shared.handleIncomingNotification(userInfo: notification.request.content.userInfo)
            completionHandler([.list, .banner, .sound])
            return
        }

        if profile.prefs.boolForKey(PendingAccountDisconnectedKey) ?? false {
            profile.removeAccount()

            // show the notification
            completionHandler([.list, .banner, .sound])
        } else {
            profile.pollCommands(forcePoll: true)
            completionHandler([])
        }
    }
}

extension AppDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AgentNotiFeature.shared.handleNewToken(deviceToken: deviceToken)

        var notificationAllowed = true
        if UserDefaults.standard.object(forKey: PrefsKeys.Notifications.SyncNotifications) != nil {
            notificationAllowed = UserDefaults.standard.bool(forKey: PrefsKeys.Notifications.SyncNotifications)
        }

        guard notificationAllowed else {
            RustFirefoxAccounts.shared.pushNotifications.disableNotifications()
            return
        }

        Task { [profile] in
            do {
                let autopush = try await Autopush(files: profile.files)
                try await autopush.updateToken(withDeviceToken: deviceToken)
                let fxaSubscription = try await autopush.subscribe(scope: RustFirefoxAccounts.pushScope)
                RustFirefoxAccounts.shared.pushNotifications.updatePushRegistration(
                    subscriptionResponse: fxaSubscription
                )
            } catch let error {
                logger.log(
                    "Failed to update push registration",
                    level: .warning,
                    category: .setup,
                    description: error.localizedDescription
                )
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.log("Failed to register for APNS",
                   level: .info,
                   category: .setup)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if application.applicationState != .active {
            AgentNotiFeature.shared.handleIncomingNotification(userInfo: userInfo)
        }
        completionHandler(.newData)
    }
}
