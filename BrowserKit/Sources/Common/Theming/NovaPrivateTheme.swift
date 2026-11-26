// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit

public struct NovaPrivateTheme: Theme {
    public var type: ThemeType = .privateMode
    private let palette = NovaPrivateColourPalette()
    public var colors: ThemeColourPalette { palette }
    public var isNova = true

    public init() {}
}

private struct NovaPrivateColourPalette: ThemeColourPalette {
    private let fallbackPalette: ThemeColourPalette = PrivateModeTheme().colors

    // MARK: - Layer

    var layer1: UIColor = NovaColors.Gray80
    var layer2: UIColor = NovaColors.Gray60
    var layer3: UIColor = NovaColors.Gray65
    var layer4: UIColor = NovaColors.Gray70
    var layer5Hover: UIColor = NovaColors.Gray65
    var layerSurfaceLow = NovaColors.Gray80
    var layerSurfaceMedium = NovaColors.Gray70
    var layerSurfaceMediumAlt: UIColor = NovaColors.Gray65
    var layerSurfaceMediumAltGlass = NovaColors.Gray70
    var layerSurfaceMediumAlpha = NovaColors.Gray70.withAlphaComponent(0.4)
    var layerAccentSubtle: UIColor = NovaColors.Gray55
    var layerInverse: UIColor = NovaColors.Gray30
    var layerWarning: UIColor = NovaColors.Yellow70
    var layerSuccess: UIColor = NovaColors.Green70
    var layerCritical: UIColor = NovaColors.Red70
    var layerInformation: UIColor = NovaColors.Blue70
    var layerSepia: UIColor = NovaColors.Yellow0
    var layerAutofillText: UIColor = NovaColors.Gray30.withAlphaComponent(0.55)
    var layerSelectedText: UIColor = NovaColors.Gray30.withAlphaComponent(0.55)
    var layerGlassTintNova: UIColor = .clear
    var layerGlassSelectedFill: UIColor = NovaColors.Gray80
    var layerAccentPrivateNonOpaque: UIColor { layerAccentSubtle }
    var layerToolbarGlass: UIColor = NovaColors.Gray60

    // MARK: - Action

    var actionPrimary: UIColor = NovaColors.Gray30
    var actionPrimaryHover: UIColor = NovaColors.Gray40
    var actionPrimaryDisabled: UIColor = NovaColors.Gray30.withAlphaComponent(0.4)
    var actionSecondary: UIColor = NovaColors.Gray55
    var actionSecondaryHover: UIColor = NovaColors.Gray60
    var actionSecondaryDisabled: UIColor = NovaColors.Gray55.withAlphaComponent(0.5)
    var actionWarning: UIColor = NovaColors.Yellow30
    var actionSuccess: UIColor = NovaColors.Green30
    var actionCritical: UIColor = NovaColors.Red30
    var actionInformation: UIColor = NovaColors.Blue30
    var formKnob: UIColor = NovaColors.White
    var formSurfaceOff: UIColor = NovaColors.Gray55
    var actionTabActive: UIColor = NovaColors.Gray70
    var actionTabInactive: UIColor = NovaColors.Gray80
    var actionCloseButton: UIColor = NovaColors.Gray70

    // MARK: - Text

    var textPrimary: UIColor = NovaColors.Gray0
    var textSecondary: UIColor = NovaColors.Gray0.withAlphaComponent(0.7)
    var textDisabled: UIColor = NovaColors.Gray0.withAlphaComponent(0.4)
    var textAccent: UIColor = NovaColors.Gray25
    var textCritical: UIColor = NovaColors.Red30
    var textInverted: UIColor = NovaColors.Gray80
    var textInvertedDisabled: UIColor = NovaColors.Gray80.withAlphaComponent(0.4)
    var textOnDark: UIColor = NovaColors.Gray0
    var textOnLight: UIColor = NovaColors.Gray80
    var textColorPrimary: UIColor = NovaColors.Gray0
    var textToast: UIColor = NovaColors.Gray50

    // MARK: - Icon

    var iconPrimary: UIColor = NovaColors.Gray0
    var iconSecondary: UIColor = NovaColors.Gray0.withAlphaComponent(0.7)
    var iconDisabled: UIColor = NovaColors.Gray0.withAlphaComponent(0.4)
    var iconAccent: UIColor = NovaColors.Gray25
    var iconCritical: UIColor = NovaColors.Red30
    var iconInverted: UIColor = NovaColors.Gray80
    var iconOnColor: UIColor = NovaColors.Gray0
    var iconOnColorDisabled: UIColor = NovaColors.Gray0.withAlphaComponent(0.4)
    var iconSpinner: UIColor = NovaColors.Gray40
    var iconPrivate: UIColor = NovaColors.Gray40

    // MARK: - Border

    var borderPrimary: UIColor = NovaColors.Gray65
    var borderStrong: UIColor = NovaColors.Gray60
    var borderInverted: UIColor = NovaColors.Gray15
    var borderAccentToast: UIColor = NovaColors.Gray55
    var borderRadioButtonDefault: UIColor = NovaColors.Gray45

    // MARK: - Shadow

    var shadowSubtle: UIColor = NovaColors.Gray80.withAlphaComponent(0.10)
    var shadowDefault: UIColor = NovaColors.Gray80.withAlphaComponent(0.12)
    var shadowStrong: UIColor = NovaColors.Gray80.withAlphaComponent(0.16)
    var shadowBorder: UIColor = NovaColors.Gray65.withAlphaComponent(0.50)

    // MARK: - Gradients

    var gradient = Gradient(colors: [NovaColors.Gray60, NovaColors.Gray50])
    var gradientAccent = Gradient(colors: [NovaColors.Gray30, NovaColors.Gray50])
    var gradientAccentSubtle = Gradient(colors: [
        NovaColors.Gray80,
        NovaColors.Gray80
    ])
    var gradientAIStrong = Gradient(colors: [
        NovaColors.Violet50,
        NovaColors.Pink40,
        NovaColors.Orange30
    ])
    var gradientBorder = Gradient(colors: [NovaColors.Gray30, NovaColors.Gray50])
    var gradientPrivacy = Gradient(colors: [
        NovaColors.Gray55,
        NovaColors.Gray40
    ])
    var gradientPrivacyMask = Gradient(colors: [NovaColors.White, NovaColors.Gray25])
    var gradientWidgetSurface = Gradient(colors: [.clear]) // widgets don't have private mode
    var gradientWidgetSurfaceStandard = Gradient(colors: [.clear]) // widgets don't have private mode
    var gradientWidgetSurfacePrivate = Gradient(colors: [.clear]) // widgets don't have private mode
    var gradientAIStrongStop1: UIColor = NovaColors.Violet50
    var gradientAIStrongStop2: UIColor = NovaColors.Pink40
    var gradientAIStrongStop3: UIColor = NovaColors.Orange30

    // Default values from PrivateModeTheme
    var layerGradient: Gradient { fallbackPalette.layerGradient }
    var layerGradientURL: Gradient { fallbackPalette.layerGradientURL }
    var layerGradientSummary: Gradient { fallbackPalette.layerGradientSummary }
    var layerScrim: UIColor { fallbackPalette.layerScrim }
    var layerCriticalSubdued: UIColor { fallbackPalette.layerCriticalSubdued }
    var layerEmphasis: UIColor { fallbackPalette.layerEmphasis }
    var indicatorActive: UIColor { fallbackPalette.indicatorActive }
    var indicatorInactive: UIColor { fallbackPalette.indicatorInactive }
    var iconAccentViolet: UIColor { fallbackPalette.iconAccentViolet }
    var iconAccentBlue: UIColor { fallbackPalette.iconAccentBlue }
    var iconAccentPink: UIColor { fallbackPalette.iconAccentPink }
    var iconAccentGreen: UIColor { fallbackPalette.iconAccentGreen }
    var iconAccentYellow: UIColor { fallbackPalette.iconAccentYellow }

    // MARK: - Deprecated
    var layer5: UIColor { layerSurfaceMedium }
    var layerGradientOverlay: Gradient { fallbackPalette.layerGradientOverlay }
    var layerHomepage: Gradient { fallbackPalette.layerHomepage }
    var layerAccentNonOpaque: UIColor { fallbackPalette.layerAccentNonOpaque }
    var layerAccentPrivate: UIColor { fallbackPalette.layerAccentPrivate }
    var gradientOnboardingStop1: UIColor { fallbackPalette.gradientOnboardingStop1 }
    var gradientOnboardingStop2: UIColor { fallbackPalette.gradientOnboardingStop2 }
    var gradientOnboardingStop3: UIColor { fallbackPalette.gradientOnboardingStop3 }
    var gradientOnboardingStop4: UIColor { fallbackPalette.gradientOnboardingStop4 }
    var iconRatingNeutral: UIColor { fallbackPalette.iconRatingNeutral }
    var borderSecondary: UIColor { fallbackPalette.borderSecondary }
    var borderAccent: UIColor { fallbackPalette.borderAccent }
    var borderAccentNonOpaque: UIColor { fallbackPalette.borderAccentNonOpaque }
    var borderAccentPrivate: UIColor { fallbackPalette.borderAccentPrivate }
    var borderToolbarDivider: UIColor { fallbackPalette.borderToolbarDivider }

    var faviconLetterColorSet: FaviconLetterColorSet = NovaFaviconColorSet()
}
