import AppKit
import SwiftUI

/// Transcribed 1:1 from `docs/design-handoff/handoff/tokens.json` (Phase 2, §7.1).
/// Views must never contain literal colours, sizes, radii or durations — everything lives here.
enum Tokens {

    // MARK: - Colour

    /// Appearance-aware colour. Resolves light/dark and the Increase Contrast variants.
    struct ThemedColor {
        let light: NSColor
        let dark: NSColor
        let highContrastLight: NSColor
        let highContrastDark: NSColor

        init(_ light: String, _ dark: String, hcLight: String? = nil, hcDark: String? = nil) {
            self.light = NSColor(hex: light)
            self.dark = NSColor(hex: dark)
            self.highContrastLight = NSColor(hex: hcLight ?? light)
            self.highContrastDark = NSColor(hex: hcDark ?? dark)
        }

        var nsColor: NSColor {
            NSColor(name: nil) { appearance in
                switch appearance.bestMatch(from: [.aqua, .darkAqua,
                                                   .accessibilityHighContrastAqua,
                                                   .accessibilityHighContrastDarkAqua]) {
                case .darkAqua: return self.dark
                case .accessibilityHighContrastAqua: return self.highContrastLight
                case .accessibilityHighContrastDarkAqua: return self.highContrastDark
                default: return self.light
                }
            }
        }

        var color: Color { Color(nsColor: nsColor) }
    }

    enum Palette {
        static let textPrimary = ThemedColor("#000000D9", "#FFFFFFEB", hcLight: "#000000", hcDark: "#FFFFFF")
        static let textSecondary = ThemedColor("#00000080", "#FFFFFF8C", hcLight: "#000000B3", hcDark: "#FFFFFFBF")
        static let textTertiary = ThemedColor("#00000059", "#FFFFFF66", hcLight: "#00000080", hcDark: "#FFFFFF99")
        static let onAccent = ThemedColor("#FFFFFF", "#FFFFFF")
        static let invalid = ThemedColor("#C93832", "#FF6961", hcLight: "#A62E29", hcDark: "#FF8A82")
        static let destructive = ThemedColor("#C93832", "#FF6961")
        static let success = ThemedColor("#28A745", "#30D158")
        static let separator = ThemedColor("#00000017", "#FFFFFF1F", hcLight: "#00000033", hcDark: "#FFFFFF40")
        static let strokeGlassTop = ThemedColor("#FFFFFFB3", "#FFFFFF29")
        static let strokeGlassBottom = ThemedColor("#0000000D", "#0000004D")
        static let fieldBackground = ThemedColor("#FFFFFF99", "#FFFFFF17")
        static let rowHover = ThemedColor("#00000009", "#FFFFFF09")
        static let trackingIndicator = ThemedColor("#28A745", "#30D158")
        static let pausedIndicator = ThemedColor("#B08325", "#FFD60A")
        static let idleIndicator = ThemedColor("#00000073", "#FFFFFF73")
        static let invalidFieldBackground = ThemedColor("#FF453A21", "#FF453A2E")
        static let autoHideDrain = ThemedColor("#00000038", "#FFFFFF42")
        /// Today-list times sit a step darker than secondary text (artboard: rgba(0,0,0,0.75)).
        static let rowTime = ThemedColor("#000000BF", "#FFFFFFBF")
        /// Secondary button fill — a neutral grey, not the white of a field.
        static let buttonSecondary = ThemedColor("#0000000F", "#FFFFFF1A")
        /// The ⌘⌫ chip beside Discard is tinted with the destructive colour, not neutral.
        static let discardHint = ThemedColor("#C938321F", "#FF69611F")

        /// The design uses the system accent throughout; nothing depends on it being blue.
        static var accent: Color { Color(nsColor: .controlAccentColor) }

        /// `rowSelected`: accent@21% light / accent@29% dark.
        static func rowSelected(_ scheme: ColorScheme) -> Color { accent.opacity(scheme == .dark ? 0.29 : 0.21) }
        /// `todayColumn`: accent@10% light / accent@16% dark.
        static func todayColumn(_ scheme: ColorScheme) -> Color { accent.opacity(scheme == .dark ? 0.16 : 0.10) }
    }

    // MARK: - Material

    struct MaterialStyle {
        let material: NSVisualEffectView.Material
        let blending: NSVisualEffectView.BlendingMode
        let tint: ThemedColor
        let fallback: ThemedColor
    }

    enum Materials {
        static let panel = MaterialStyle(material: .hudWindow, blending: .behindWindow,
                                         tint: ThemedColor("#FFFFFF66", "#26262E99"),
                                         fallback: ThemedColor("#F2F2F6", "#1E1E23"))
        static let panelPassive = MaterialStyle(material: .hudWindow, blending: .behindWindow,
                                                tint: ThemedColor("#FFFFFF40", "#26262E66"),
                                                fallback: ThemedColor("#F2F2F6", "#1E1E23"))
        static let window = MaterialStyle(material: .underWindowBackground, blending: .behindWindow,
                                          tint: ThemedColor("#FAFAFDBF", "#2C2C34B8"),
                                          fallback: ThemedColor("#F4F4F7", "#232329"))
        static let popover = MaterialStyle(material: .popover, blending: .behindWindow,
                                           tint: ThemedColor("#FCFCFFEB", "#32323ADD"),
                                           fallback: ThemedColor("#FCFCFF", "#32323A"))
        static let sheet = MaterialStyle(material: .sheet, blending: .withinWindow,
                                         tint: ThemedColor("#FAFAFEDE", "#2E2E36D9"),
                                         fallback: ThemedColor("#FAFAFE", "#2E2E36"))
        /// Fields are not a material: a flat tint over whatever is behind them.
        static let field = MaterialStyle(material: .hudWindow, blending: .withinWindow,
                                         tint: ThemedColor("#FFFFFF99", "#FFFFFF17"),
                                         fallback: ThemedColor("#FFFFFF", "#2A2A31"))
    }

    // MARK: - Type

    struct FontToken {
        enum Family { case text, display, rounded }
        let family: Family
        let size: CGFloat
        let weight: NSFont.Weight
        let tracking: CGFloat
        let tabular: Bool

        var nsFont: NSFont {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            var descriptor = base.fontDescriptor
            if family == .rounded, let rounded = descriptor.withDesign(.rounded) {
                descriptor = rounded
            }
            if tabular {
                descriptor = descriptor.addingAttributes([
                    .featureSettings: [[
                        NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                        NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
                    ]]
                ])
            }
            return NSFont(descriptor: descriptor, size: size) ?? base
        }

        var font: Font { Font(nsFont) }
    }

    enum Typography {
        static let heading = FontToken(family: .text, size: 11, weight: .medium, tracking: 0, tabular: false)
        static let body = FontToken(family: .text, size: 13, weight: .regular, tracking: 0, tabular: false)
        static let caption = FontToken(family: .text, size: 10, weight: .regular, tracking: 0, tabular: false)
        static let timeAdd = FontToken(family: .rounded, size: 26, weight: .medium, tracking: 0.3, tabular: true)
        static let timeLarge = FontToken(family: .rounded, size: 28, weight: .medium, tracking: 0.3, tabular: true)
        static let timeCell = FontToken(family: .text, size: 12, weight: .regular, tracking: 0, tabular: true)
        static let listRow = FontToken(family: .text, size: 13, weight: .regular, tracking: 0, tabular: false)
        static let listRowCurrent = FontToken(family: .text, size: 13, weight: .medium, tracking: 0, tabular: false)
        static let periodTitle = FontToken(family: .display, size: 15, weight: .semibold, tracking: 0, tabular: false)
        static let menuBarTime = FontToken(family: .text, size: 11.5, weight: .regular, tracking: 0, tabular: true)
        static let keyboardHint = FontToken(family: .text, size: 10, weight: .regular, tracking: 0, tabular: false)
        /// Tabular, so three figures side by side do not shuffle as they tick.
        static let loadValue = FontToken(family: .text, size: 11, weight: .medium, tracking: 0, tabular: true)
    }

    // MARK: - Metrics

    enum Radius {
        static let panel: CGFloat = 18
        static let window: CGFloat = 12
        static let sheet: CGFloat = 12
        static let popover: CGFloat = 12
        static let field: CGFloat = 10
        static let button: CGFloat = 9
        static let row: CGFloat = 8
        static let cell: CGFloat = 6
        static let chip: CGFloat = 12
        static let kbdHint: CGFloat = 4
    }

    enum Space {
        /// The panel's own padding is 14 top, 16 elsewhere (artboard: `padding:14px 16px 16px`).
        static let panelTop: CGFloat = 14
        /// Horizontal insets the artboard uses inside the field and the list rows.
        static let fieldInset: CGFloat = 10
        static let rowInset: CGFloat = 9
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 24
    }

    enum Size {
        static let popupWidth: CGFloat = 380
        static let popupWidthMax: CGFloat = 400
        static let popupMinHeight: CGFloat = 150
        static let popupMaxHeight: CGFloat = 320
        static let fieldHeight: CGFloat = 30
        static let buttonHeight: CGFloat = 28
        static let listRowHeight: CGFloat = 28
        static let dropdownRowHeight: CGFloat = 26
        static let todayListMaxVisibleRows = 6
        static let toolbarHeight: CGFloat = 52
        /// The Reports toolbar shares its row with the window's traffic lights.
        static let trafficLightInset: CGFloat = 78
        static let reportsDefault = CGSize(width: 860, height: 560)
        /// Below this the toolbar cannot hold its controls, so the window refuses to go smaller.
        static let reportsMinimum = CGSize(width: 780, height: 420)
        static let settingsWidth: CGFloat = 480
        /// Header row and indicator dot, from the popup anatomy in HANDOFF.md.
        static let headerHeight: CGFloat = 20
        static let indicatorDot: CGFloat = 6
        /// Live status as a ring around the project's colour swatch, rather than a second dot.
        static let indicatorRing: CGFloat = 1.5
        static let indicatorRingGap: CGFloat = 2
        static let iconButton: CGFloat = 20
        static let pausePopoverWidth: CGFloat = 240
        static let overflowMenuWidth: CGFloat = 190
        /// Wider than the overflow menu: its rows carry a trailing hint, and the timer slider
        /// wants every point it can get.
        static let taskMenuWidth: CGFloat = 230
        static let autoHideDrainHeight: CGFloat = 2
    }

    struct ShadowToken {
        let light: (color: NSColor, blur: CGFloat, y: CGFloat)
        let dark: (color: NSColor, blur: CGFloat, y: CGFloat)

        func color(_ scheme: ColorScheme) -> Color { Color(nsColor: scheme == .dark ? dark.color : light.color) }
        /// SwiftUI blur radius is roughly half a design blur.
        func radius(_ scheme: ColorScheme) -> CGFloat { (scheme == .dark ? dark.blur : light.blur) / 2 }
        func y(_ scheme: ColorScheme) -> CGFloat { scheme == .dark ? dark.y : light.y }
    }

    enum Shadows {
        static let panel = ShadowToken(light: (NSColor(hex: "#00000038"), 40, 12), dark: (NSColor(hex: "#0000008C"), 40, 12))
        static let panelPassive = ShadowToken(light: (NSColor(hex: "#00000026"), 28, 8), dark: (NSColor(hex: "#00000066"), 28, 8))
        static let popover = ShadowToken(light: (NSColor(hex: "#0000004D"), 48, 16), dark: (NSColor(hex: "#00000099"), 48, 16))
        static let window = ShadowToken(light: (NSColor(hex: "#00000047"), 60, 20), dark: (NSColor(hex: "#00000080"), 60, 20))
    }

    // MARK: - Motion

    struct MotionToken {
        let duration: Double          // seconds
        let curve: Animation

        init(ms: Double, curve: Animation) {
            self.duration = ms / 1000
            self.curve = curve
        }

        /// Reduce Motion turns every animation into a 120 ms crossfade.
        func animation(reduceMotion: Bool) -> Animation {
            reduceMotion ? Motion.reduceMotionFallback.curve : curve
        }
    }

    enum Motion {
        static let popupAppearPassive = MotionToken(ms: 180, curve: .easeOut(duration: 0.18))
        static let popupAppearFocused = MotionToken(ms: 180, curve: .easeOut(duration: 0.18))
        static let popupDismiss = MotionToken(ms: 120, curve: .easeIn(duration: 0.12))
        static let listOpen = MotionToken(ms: 160, curve: .easeOut(duration: 0.16))
        static let highlightMove = MotionToken(ms: 90, curve: .easeOut(duration: 0.09))
        static let digitTick = MotionToken(ms: 150, curve: .linear(duration: 0.15))
        static let commit = MotionToken(ms: 250, curve: .easeOut(duration: 0.25))
        /// Confirm bounce on the amount label: shrink, overshoot, settle, then dismiss.
        /// 110 + 150 + 100 + 120 ms of dismiss = 480 ms, inside the half second asked for.
        static let commitShrink = MotionToken(ms: 110, curve: .easeIn(duration: 0.11))
        static let commitMagnify = MotionToken(ms: 150, curve: .easeOut(duration: 0.15))
        static let commitSettle = MotionToken(ms: 100, curve: .easeInOut(duration: 0.10))
        static let invalidShake = MotionToken(ms: 300, curve: .easeInOut(duration: 0.3))
        static let pauseCrossfade = MotionToken(ms: 200, curve: .easeInOut(duration: 0.2))
        static let discard = MotionToken(ms: 250, curve: .easeIn(duration: 0.25))
        /// The amount field collapses and clears before the panel dismisses (120 ms + 120 ms).
        static let discardCollapse = MotionToken(ms: 120, curve: .easeIn(duration: 0.12))
        static let autoHide = MotionToken(ms: 20000, curve: .linear(duration: 20))
        /// Tasks: a rewarding pop in, a strike-through slide out, a shrink on delete.
        static let taskAppear = MotionToken(ms: 220, curve: .spring(response: 0.26, dampingFraction: 0.62))
        static let taskComplete = MotionToken(ms: 280, curve: .easeIn(duration: 0.28))
        static let taskDelete = MotionToken(ms: 180, curve: .easeIn(duration: 0.18))
        static let reduceMotionFallback = MotionToken(ms: 120, curve: .linear(duration: 0.12))
    }

    /// Button label widths from the artboard's component sheet: the three are not equal.
    enum ButtonInset {
        static let discard: CGFloat = 12
        static let secondary: CGFloat = 13
        static let primary: CGFloat = 14
    }

    /// The one sound the app makes: a timer reaching zero (T-12). A system sound rather than
    /// a bundled one, so it follows whatever the user has set their alert volume to.
    enum Sound {
        static let timerExpired = NSSound.Name("Submarine")
    }

    /// The 24-hour timeline strip (TL-01 … TL-06). Not from `tokens.json`; there was no such
    /// thing in the handoff.
    enum Strip {
        /// Tall enough that a magnified mark has somewhere to grow into without the popup
        /// changing height under the cursor.
        static let height: CGFloat = 22
        static let markHeight: CGFloat = 10
        /// 348 pt of content over 48 half-hour brackets is a 7.25 pt pitch; the mark takes
        /// most of it and the rest is the gap.
        static let markWidth: CGFloat = 5
        static let trackHeight: CGFloat = 1
        /// How much wider the mark under the cursor gets, and how far the bulge reaches.
        /// Kept modest on purpose: past about 1.5 the magnified marks overlap their
        /// neighbours into a single blob and the bulge stops reading as marks at all.
        /// Height is the dimension with room to grow, so height does most of the work.
        static let widthGain: CGFloat = 1.4
        /// ±2 hours at half-hour brackets.
        static let magnifyRadius = 4
        static let tick: CGFloat = 3
        static let tickTall: CGFloat = 6
        static let tickEveryHours = 6
        static let captionGap: CGFloat = 3
    }

    /// The system load bar across the top of the popup. Not from `tokens.json`: there was no
    /// such thing in the handoff.
    enum Load {
        static let inset: CGFloat = 7
        static let labelGap: CGFloat = 5
        static let pinnedTint: Double = 0.12
        /// Past this share of capacity a figure is the machine's problem, and says so in the
        /// colour the rest of the app uses for trouble.
        static let strainedAt: Double = 0.85
        static let gauge = (height: CGFloat(3), gap: CGFloat(4))
    }

    /// The timer slider (T-10). Its own group: it replaced the handoff's list of fixed
    /// durations, so none of these numbers come from `tokens.json`.
    enum Slider {
        static let bandHeight: CGFloat = 22
        static let scaleHeight: CGFloat = 12
        static let trackHeight: CGFloat = 4
        static let knob: CGFloat = 14
        static let knobRing: CGFloat = 1.5
        static let knobHoverScale: CGFloat = 1.15
        /// Ticks for the hour and for the timer already set.
        static let markerHeight: CGFloat = 9
        static let markerWidth: CGFloat = 1.5
    }

    /// The confirm bounce: the amount label pulls back, overshoots and settles.
    enum Confirm {
        static let shrunkScale: CGFloat = 0.82
        static let magnifiedScale: CGFloat = 1.14
    }

    // MARK: - Focus

    enum Focus {
        static let ringWidth: CGFloat = 3
        static let rowRingWidth: CGFloat = 2.5
        static let borderWidth: CGFloat = 0.5
        /// Increase Contrast lifts the ring from 32 % to 50 %.
        static func ringOpacity(_ increased: Bool) -> Double { increased ? 0.5 : 0.32 }
        static func hairlineWidth(_ increased: Bool) -> CGFloat { increased ? 1 : 0.5 }
    }

    /// Categorical series colours for the chart. Both columns are the validated reference
    /// palette (dataviz skill): worst adjacent CVD ΔE 9.1 light / 8.4 dark, normal-vision 19.6 /
    /// 19.3. Slots are assigned in fixed order and never cycled — a ninth project folds into
    /// "Other" rather than repeating a hue.
    enum Series {
        static let slots: [ThemedColor] = [
            ThemedColor("#2a78d6", "#3987e5"),   // blue
            ThemedColor("#eb6834", "#d95926"),   // orange
            ThemedColor("#1baf7a", "#199e70"),   // aqua
            ThemedColor("#eda100", "#c98500"),   // yellow
            ThemedColor("#e87ba4", "#d55181"),   // magenta
            ThemedColor("#008300", "#008300"),   // green
            ThemedColor("#4a3aa7", "#9085e9"),   // violet
            ThemedColor("#e34948", "#e66767"),   // red
        ]
        static let other = ThemedColor("#8A8A8E", "#98989D")
        static let maxSlots = 8

        static func color(slot: Int) -> Color {
            slot >= 0 && slot < slots.count ? slots[slot].color : other.color
        }

        /// Stacked segments and adjacent bars are separated by a surface-coloured gap.
        static let gap: CGFloat = 2
        static let barCorner: CGFloat = 4
    }

    // MARK: - Icons

    enum Icons {
        static let pause = "pause.fill"
        static let resume = "play.fill"
        static let export = "square.and.arrow.up"
        static let addProject = "plus"
        static let navBack = "chevron.left"
        static let navForward = "chevron.right"
        static let dropdownChevron = "chevron.down"
        static let settings = "gearshape"
        static let reports = "chart.bar"
        static let quit = "power"
    }
}

extension NSColor {
    /// `#RGB`, `#RRGGBB` or `#RRGGBBAA`.
    convenience init(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        if string.count == 3 { string = string.map { "\($0)\($0)" }.joined() }
        if string.count == 6 { string += "FF" }
        let value = UInt64(string, radix: 16) ?? 0xFF
        self.init(srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
                  green: CGFloat((value >> 16) & 0xFF) / 255,
                  blue: CGFloat((value >> 8) & 0xFF) / 255,
                  alpha: CGFloat(value & 0xFF) / 255)
    }
}

extension View {
    func font(_ token: Tokens.FontToken) -> some View {
        self.font(token.font).tracking(token.tracking)
    }

    func shadow(_ token: Tokens.ShadowToken, _ scheme: ColorScheme) -> some View {
        self.shadow(color: token.color(scheme), radius: token.radius(scheme), y: token.y(scheme))
    }
}
