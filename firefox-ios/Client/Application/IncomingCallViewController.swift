// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Common

public final class IncomingCallViewController: UIViewController {
    public static weak var activeInstance: IncomingCallViewController?

    public var callerName: String = "Cuộc gọi đến..."
    public var callStatusText: String = "Đang đổ chuông..."
    public var callUrl: String = ""
    public var callKey: String = ""
    public var avatarUrl: String?
    public var timeoutInterval: TimeInterval = 45.0
    public var onCallAccepted: ((String) -> Void)?
    public var onCallDeclined: ((String) -> Void)?
    private var callTimeoutTimer: Timer?

    public init() {
        super.init(nibName: nil, bundle: nil)
        Self.activeInstance = self
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        Self.activeInstance = self
    }

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.layer.cornerRadius = 55
        iv.layer.masksToBounds = true
        iv.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        iv.image = UIImage(systemName: "person.crop.circle.fill")
        iv.tintColor = .white
        return iv
    }()

    private let callerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 26, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = UIColor(white: 1.0, alpha: 0.8)
        label.textAlignment = .center
        return label
    }()

    private let declineButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.backgroundColor = UIColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1.0)
        btn.layer.cornerRadius = 35
        btn.setImage(UIImage(systemName: "phone.down.fill"), for: .normal)
        btn.tintColor = .white
        return btn
    }()

    private let acceptButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.backgroundColor = UIColor(red: 0.25, green: 0.85, blue: 0.35, alpha: 1.0)
        btn.layer.cornerRadius = 35
        btn.setImage(UIImage(systemName: "phone.fill"), for: .normal)
        btn.tintColor = .white
        return btn
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()
        Self.activeInstance = self
        view.backgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1.0)

        setupUI()
        callerLabel.text = callerName
        statusLabel.text = callStatusText

        if let avatarStr = avatarUrl, let url = URL(string: avatarStr) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data = data, let img = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.avatarImageView.image = img
                    }
                }
            }.resume()
        }

        declineButton.addTarget(self, action: #selector(handleDecline), for: .touchUpInside)
        acceptButton.addTarget(self, action: #selector(handleAccept), for: .touchUpInside)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(remoteCallEnded),
            name: NSNotification.Name("AgentNotiRemoteCallEnded"),
            object: nil
        )

        // Hẹn giờ tự ngắt nếu không thao tác
        callTimeoutTimer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { [weak self] _ in
            self?.handleTimeout()
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        callTimeoutTimer?.invalidate()
        callTimeoutTimer = nil
        if Self.activeInstance === self {
            Self.activeInstance = nil
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        view.addSubview(avatarImageView)
        view.addSubview(callerLabel)
        view.addSubview(statusLabel)
        view.addSubview(declineButton)
        view.addSubview(acceptButton)

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            avatarImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 110),
            avatarImageView.heightAnchor.constraint(equalToConstant: 110),

            callerLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 24),
            callerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            callerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            statusLabel.topAnchor.constraint(equalTo: callerLabel.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            declineButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            declineButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 60),
            declineButton.widthAnchor.constraint(equalToConstant: 70),
            declineButton.heightAnchor.constraint(equalToConstant: 70),

            acceptButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            acceptButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),
            acceptButton.widthAnchor.constraint(equalToConstant: 70),
            acceptButton.heightAnchor.constraint(equalToConstant: 70)
        ])
    }

    @objc private func handleDecline() {
        callTimeoutTimer?.invalidate()
        callTimeoutTimer = nil
        AgentNotiAudioPlayer.shared.playEndCallSound()
        AgentNotiFeature.shared.removeDeliveredCallNotification(callKey: callKey)
        onCallDeclined?(callKey)
        dismiss(animated: true)
    }

    @objc private func handleAccept() {
        callTimeoutTimer?.invalidate()
        callTimeoutTimer = nil
        AgentNotiAudioPlayer.shared.stopCallRingtone()
        AgentNotiFeature.shared.removeDeliveredCallNotification(callKey: callKey)
        onCallAccepted?(callUrl)
        dismiss(animated: true)
    }

    @objc private func handleTimeout() {
        AgentNotiAudioPlayer.shared.playEndCallSound()
        AgentNotiFeature.shared.removeDeliveredCallNotification(callKey: callKey)
        onCallDeclined?(callKey)
        dismiss(animated: true)
    }

    @objc private func remoteCallEnded() {
        callTimeoutTimer?.invalidate()
        callTimeoutTimer = nil
        dismiss(animated: true)
    }
}
