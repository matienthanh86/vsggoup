// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import UIKit

/// Utility functions related to SUMO and Webcompat
public enum SupportUtils {
    public static var URLForPrivateBrowsingLearnMore: URL? {
        return URL(string: "https://vsg.top")
    }

    public static var URLForGetHelp: URL? {
        return URL(string: "https://vsg.top")
    }

    public static var URLForPocketLearnMore: URL? {
        return URL(string: "https://vsg.top")
    }

    public static var URLForTermsOfUse: URL? {
        return URL(string: "https://vsg.top/terms")
    }

    public static var URLForPrivacyNotice: URL? {
        return URL(string: "https://vsg.top/privacy")
    }

    public static var URLForUpdatedPrivacyNotice: URL? {
        return URL(string: "https://vsg.top/privacy")
    }

    public static var URLForUpdatedPrivacyNoticeDiff: URL? {
        return URL(string: "https://vsg.top/privacy")
    }

    public static var URLForRelayAccountManagement: URL? {
        return URL(string: "https://vsg.top")
    }

    public static var URLForRelayMaskLearnMoreArticle: URL? {
        return URL(string: "https://vsg.top")
    }

    public static var URLForConnectionNotSecureLearnMore: URL? {
        return URL(string: "https://vsg.top")
    }

    public static func URLForTopic(_ topic: String, useMobilePath: Bool = true) -> URL? {
        return URL(string: "https://vsg.top")
    }

    public static func URLForPrivacyNotice(source: String, campaign: String, content: String?) -> URL? {
        return URL(string: "https://vsg.top/privacy")
    }
}
