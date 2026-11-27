// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import WebKit

/// Draggable floating AI button that snaps to the left or right screen edge
/// and persists its position across sessions.
final class FloatingAIButton: UIView {
    private enum Constants {
        static let size: CGFloat = 52
        static let horizontalMargin: CGFloat = 12
        static let topExtraMargin: CGFloat = 60
        static let bottomExtraMargin: CGFloat = 76
        static let defaultYRatio: CGFloat = 0.75
        static let isRightEdgeKey = "dino_ai_floating_button_is_right_edge"
        static let yRatioKey = "dino_ai_floating_button_y_ratio"
    }

    var onTap: (() -> Void)?

    private let gradientLayer = CAGradientLayer()
    private let iconView = UIImageView()
    private var isDragging = false
    private var hasInitializedPosition = false

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: Constants.size, height: Constants.size))
        setupUI()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = bounds.width / 2
        layer.cornerRadius = bounds.width / 2
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    private func setupUI() {
        gradientLayer.colors = [
            UIColor(red: 91 / 255, green: 92 / 255, blue: 230 / 255, alpha: 1).cgColor,
            UIColor(red: 123 / 255, green: 66 / 255, blue: 246 / 255, alpha: 1).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradientLayer, at: 0)

        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 8

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        iconView.image = UIImage(systemName: "sparkles", withConfiguration: symbolConfig)
        iconView.tintColor = .white
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalTo: widthAnchor),
            iconView.heightAnchor.constraint(equalTo: heightAnchor)
        ])

        accessibilityLabel = "DINO AI"
        isAccessibilityElement = true
    }

    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)
    }

    @objc private func handleTap() {
        UIView.animate(withDuration: 0.1, animations: {
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.15) {
                self.transform = .identity
            }
        }
        onTap?()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)
        let allowedRect = allowedCenterRect(in: superview)

        switch gesture.state {
        case .began:
            isDragging = true
        case .changed:
            let nextX = min(max(center.x + translation.x, allowedRect.minX), allowedRect.maxX)
            let nextY = min(max(center.y + translation.y, allowedRect.minY), allowedRect.maxY)
            center = CGPoint(x: nextX, y: nextY)
            gesture.setTranslation(.zero, in: superview)
        case .ended, .cancelled, .failed:
            isDragging = false
            snapToNearestEdge(in: allowedRect)
        default:
            break
        }
    }

    private func allowedCenterRect(in superview: UIView) -> CGRect {
        let safe = superview.safeAreaInsets
        let half = Constants.size / 2
        let minX = safe.left + Constants.horizontalMargin + half
        let maxX = max(minX, superview.bounds.width - safe.right - Constants.horizontalMargin - half)
        let minY = safe.top + Constants.topExtraMargin + half
        let maxY = max(minY, superview.bounds.height - safe.bottom - Constants.bottomExtraMargin - half)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func snapToNearestEdge(in allowedRect: CGRect) {
        let snapToRight = center.x >= allowedRect.midX
        let targetX = snapToRight ? allowedRect.maxX : allowedRect.minX
        let targetY = min(max(center.y, allowedRect.minY), allowedRect.maxY)

        let yRatio: CGFloat
        if allowedRect.height > 0 {
            yRatio = (targetY - allowedRect.minY) / allowedRect.height
        } else {
            yRatio = Constants.defaultYRatio
        }

        UserDefaults.standard.set(snapToRight, forKey: Constants.isRightEdgeKey)
        UserDefaults.standard.set(Double(yRatio), forKey: Constants.yRatioKey)

        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.5,
            options: [.allowUserInteraction]
        ) {
            self.center = CGPoint(x: targetX, y: targetY)
        }
    }

    func repositionInSuperviewIfNeeded() {
        guard !isDragging, let superview = superview, superview.bounds.width > 0 else { return }
        let allowedRect = allowedCenterRect(in: superview)

        let defaults = UserDefaults.standard
        let isRightEdge = defaults.object(forKey: Constants.isRightEdgeKey) as? Bool ?? true
        let savedRatio = defaults.object(forKey: Constants.yRatioKey) as? Double ?? Double(Constants.defaultYRatio)
        let clampedRatio = min(max(CGFloat(savedRatio), 0), 1)

        let targetX = isRightEdge ? allowedRect.maxX : allowedRect.minX
        let targetY = allowedRect.minY + allowedRect.height * clampedRatio

        if !hasInitializedPosition || abs(center.x - targetX) > 1 || abs(center.y - targetY) > 1 {
            hasInitializedPosition = true
            bounds = CGRect(x: 0, y: 0, width: Constants.size, height: Constants.size)
            center = CGPoint(x: targetX, y: targetY)
        }
    }
}

/// Persistent modal sheet hosting https://ai.dino.top with shared browser cookies.
final class DinoAIModalViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private static let aiURL = URL(string: "https://ai.dino.top")!

    var onOpenInNewTab: ((URL) -> Void)?

    private let headerView = UIView()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        let darkBg = UIColor(red: 20 / 255, green: 22 / 255, blue: 31 / 255, alpha: 1)
        webView.backgroundColor = darkBg
        webView.scrollView.backgroundColor = darkBg
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }()

    private var progressObservation: NSKeyValueObservation?
    private var hasLoadedInitialURL = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 20 / 255, green: 22 / 255, blue: 31 / 255, alpha: 1)
        setupHeader()
        setupWebView()
        loadInitialURLIfNeeded()
    }

    private func setupHeader() {
        headerView.backgroundColor = UIColor(red: 30 / 255, green: 32 / 255, blue: 48 / 255, alpha: 1)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        let iconView = UIImageView(image: UIImage(systemName: "sparkles"))
        iconView.tintColor = UIColor(red: 138 / 255, green: 130 / 255, blue: 255 / 255, alpha: 1)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "DINO AI"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let reloadButton = makeHeaderButton(systemName: "arrow.clockwise", action: #selector(didTapReload))
        let openTabButton = makeHeaderButton(systemName: "arrow.up.right.square", action: #selector(didTapOpenInTab))
        let closeButton = makeHeaderButton(systemName: "xmark", action: #selector(didTapClose))

        let buttonStack = UIStackView(arrangedSubviews: [reloadButton, openTabButton, closeButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 4
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let divider = UIView()
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        divider.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(iconView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(buttonStack)
        headerView.addSubview(divider)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 52),

            iconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            buttonStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            buttonStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            divider.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
    }

    private func makeHeaderButton(systemName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = UIColor.white.withAlphaComponent(0.85)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])
        return button
    }

    private func setupWebView() {
        progressView.progressTintColor = UIColor(red: 123 / 255, green: 66 / 255, blue: 246 / 255, alpha: 1)
        progressView.trackTintColor = .clear
        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            webView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let progress = Float(webView.estimatedProgress)
                self.progressView.isHidden = progress >= 1.0
                self.progressView.setProgress(progress, animated: true)
            }
        }
    }

    private func loadInitialURLIfNeeded() {
        guard !hasLoadedInitialURL else { return }
        hasLoadedInitialURL = true
        webView.load(URLRequest(url: Self.aiURL))
    }

    @objc private func didTapReload() {
        if webView.url == nil {
            webView.load(URLRequest(url: Self.aiURL))
        } else {
            webView.reload()
        }
    }

    @objc private func didTapOpenInTab() {
        let urlToOpen = webView.url ?? Self.aiURL
        dismiss(animated: true) { [weak self] in
            self?.onOpenInNewTab?(urlToOpen)
        }
    }

    @objc private func didTapClose() {
        dismiss(animated: true)
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if url.host?.hasSuffix("ai.dino.top") == true {
            webView.load(navigationAction.request)
        } else {
            dismiss(animated: true) { [weak self] in
                self?.onOpenInNewTab?(url)
            }
        }
        return nil
    }

    @available(iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        if origin.host.hasSuffix("dino.top") {
            decisionHandler(.grant)
        } else {
            decisionHandler(.prompt)
        }
    }
}
