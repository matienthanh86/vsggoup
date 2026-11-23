// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit

extension UIView {
    /// Convenience function to ease creating new views.
    ///
    /// Calling this function creates a new view with `translatesAutoresizingMaskIntoConstraints`
    /// set to false. Passing in an optional closure to do further configuration of the view.
    ///
    /// - Parameters:
    ///   - builder: A function that takes the newly created view.
    ///   - initializer: An optional closure that returns a custom instance of the view.
    ///   If not provided, the default initializer of `T` is used.
    /// - Returns: A newly created and configured view of type `T`.
    ///
    /// Usage:
    /// ```swift
    ///    private let button: UIButton = .build { button in
    ///        button.setTitle("Tap me!", for state: .normal)
    ///        button.backgroundColor = .systemPink
    ///    }
    /// ```
    /// You can also provide a custom initializer:
    /// ```swift
    /// private let customView: CustomView = .build(nil) {
    ///     CustomView(customParameter: "value")
    /// }
    /// ```
    public static func build<T: UIView>(
        _ builder: ((T) -> Void)? = nil,
        _ initializer: (() -> T)? = nil
    ) -> T {
        let view: T = initializer?() ?? T()
        view.translatesAutoresizingMaskIntoConstraints = false
        builder?(view)

        return view
    }

    /// Convenience function to add multiple subviews
    /// - Parameter views: A variadic parameter taking in a list of views to be added.
    ///
    /// Usage:
    /// ```
    ///    view.addSubviews(headerView, contentView, footerView)
    /// ```
    public func addSubviews(_ views: UIView...) {
        views.forEach(addSubview)
    }

    /// Convenience utility for pinning a subview to the bounds of its superview.
    public func pinToSuperview() {
        guard let parentView = superview else { return }
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parentView.topAnchor),
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
        ])
        translatesAutoresizingMaskIntoConstraints = false
    }

    /// Applies a shadow configuration to the view's layer. The shadow color is determined based on the current theme
    /// *Note: Figma's shadow "blur" value is roughly double UIKit's shadowRadius,
    /// so we divide by 2 to visually match Figma's shadow.
    /// *Note: A UIView layers `shadowPath` should be applied separately after it's bounds have been computed
    /// - Parameter shadow: The FxShadow configuration to apply
    ///
    /// Usage:
    /// ```
    ///    view.applyShadow(FxShadow.shadow200)
    /// ```
    public func applyShadow(_ shadow: FxShadow, theme: Theme) {
        let shadowColor = shadow.colorProvider(theme)

        // Apply shadow properties to the layer
        layer.shadowColor = shadowColor.cgColor
        layer.shadowOffset = shadow.offset
        layer.shadowRadius = shadow.blurRadius / 2
        layer.shadowOpacity = shadow.opacity
    }

    /// Sets the corner radius to the devices current corner radius
    public func applyScreenCornerRadius() {
        // TODO: FXIOS-14817 FXIOS-16327 Centralize a way to query device corner radius without the private api
        layer.cornerRadius = UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat ?? 0
    }
}

// MARK: - iOS 26+ Compatibility Shims for Compiling on Xcode <= 16 / iOS <= 18 SDKs
#if compiler(<6.4)
public struct UILayoutGuideRegion: Sendable {
    public enum CornerAdaptation: Sendable {
        case horizontal
    }
    public static func margins(cornerAdaptation: CornerAdaptation) -> UILayoutGuideRegion {
        return UILayoutGuideRegion()
    }
    public static func bar(onEdge: UIRectEdge, extent: CGFloat) -> UILayoutGuideRegion {
        return UILayoutGuideRegion()
    }
}

extension UIView {
    public func layoutGuide(for region: UILayoutGuideRegion) -> UILayoutGuide {
        return safeAreaLayoutGuide
    }
}

// UIGlassEffect is natively provided by UIKit in iOS 26+ SDK (Xcode 26+).
// To avoid ambiguous type collision between Common.UIGlassEffect and UIKit.UIGlassEffect
// on Xcode 26+, this compatibility shim is only compiled when LEGACY_XCODE_SHIMS is defined.
#if LEGACY_XCODE_SHIMS
open class UIGlassEffect: UIVisualEffect, @unchecked Sendable {
    public enum Style: Sendable {
        case regular
    }
    public var tintColor: UIColor?
    public var isInteractive: Bool = false

    public override init() {
        super.init()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public convenience init(style: Style) {
        self.init()
    }
}
#else
@available(iOS 26.0, *)
public typealias UIGlassEffect = UIKit.UIGlassEffect
#endif

// MARK: - UIButton.Configuration iOS 26 Glass Shims
extension UIButton.Configuration {
    @_disfavoredOverload
    public static func prominentClearGlass() -> UIButton.Configuration {
        return .plain()
    }

    @_disfavoredOverload
    public static func glass() -> UIButton.Configuration {
        return .plain()
    }

    @_disfavoredOverload
    public static func prominentGlass() -> UIButton.Configuration {
        return .filled()
    }
}

// MARK: - UIBarButtonItem iOS 26 Shims
extension UIBarButtonItem {
    public var hidesSharedBackground: Bool {
        get { return false }
        set {}
    }

    public var sharesBackground: Bool {
        get { return false }
        set {}
    }
}

extension UIBarButtonItem.Style {
    @_disfavoredOverload
    public static var prominent: UIBarButtonItem.Style {
        return .done
    }
}

// MARK: - SwiftUI iOS 26 Glass Button Style & View Modifiers Shims
import SwiftUI

#if LEGACY_XCODE_SHIMS
public struct GlassProminentButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
        }
    }
}

extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle {
    public static var glassProminent: GlassProminentButtonStyle {
        return GlassProminentButtonStyle()
    }
}
#endif

public struct ScrollEdgeEffectStyleShim: Sendable {
    public static let soft = ScrollEdgeEffectStyleShim()
}

public struct ScrollEdgeTargetShim: Sendable {
    public static let bottom = ScrollEdgeTargetShim()
    public static let all = ScrollEdgeTargetShim()
}

public struct GlassEffectDescriptorShim: Sendable {
    public static let clear = GlassEffectDescriptorShim()
    public init() {}
    public func interactive() -> GlassEffectDescriptorShim { self }
    public func tint(_ color: Color) -> GlassEffectDescriptorShim { self }
}

public struct GlassEffectShapeShim: Sendable {
    public init() {}
    public static func rect(cornerRadius: CGFloat) -> GlassEffectShapeShim {
        return GlassEffectShapeShim()
    }
}

extension View {
    @_disfavoredOverload
    @ViewBuilder
    public func safeAreaBar(edge: VerticalEdge, @ViewBuilder content: () -> some View) -> some View {
        self.safeAreaInset(edge: edge, content: content)
    }

    @_disfavoredOverload
    @ViewBuilder
    public func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyleShim, for target: ScrollEdgeTargetShim) -> some View {
        self
    }

    @_disfavoredOverload
    @ViewBuilder
    public func glassEffect(_ effect: GlassEffectDescriptorShim, in shape: GlassEffectShapeShim = GlassEffectShapeShim()) -> some View {
        self
    }
}
#endif
