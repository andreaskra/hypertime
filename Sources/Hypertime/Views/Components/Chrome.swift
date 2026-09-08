import AppKit
import SwiftUI

// MARK: - Focus ring

/// 3 pt accent glow + 0.5 pt accent border for fields and buttons; 2.5 pt full-row ring for
/// list rows. Increase Contrast lifts the glow from 32 % to 50 % (HANDOFF "Focus & keyboard").
struct FocusRing: ViewModifier {
    var isFocused: Bool
    var cornerRadius: CGFloat
    var width: CGFloat = Tokens.Focus.ringWidth
    var drawsBorder: Bool = true

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.forcesActiveAppearance) private var forcesActiveAppearance

    /// A focus ring means "typing goes here". It is a lie in a window that does not have the
    /// keyboard, so it is only drawn while the window is key.
    private var isVisible: Bool {
        isFocused && (controlActiveState == .key || forcesActiveAppearance)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isVisible, drawsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Tokens.Palette.accent, lineWidth: Tokens.Focus.borderWidth)
                }
            }
            .background {
                if isVisible {
                    RoundedRectangle(cornerRadius: cornerRadius + width / 2, style: .continuous)
                        .stroke(Tokens.Palette.accent.opacity(Tokens.Focus.ringOpacity(contrast == .increased)),
                                lineWidth: width)
                        .padding(-width / 2)
                }
            }
    }
}

extension View {
    func focusRing(_ isFocused: Bool, radius: CGFloat, width: CGFloat = Tokens.Focus.ringWidth, border: Bool = true) -> some View {
        modifier(FocusRing(isFocused: isFocused, cornerRadius: radius, width: width, drawsBorder: border))
    }
}

// MARK: - Buttons

enum HypertimeButtonKind {
    case primary, secondary, ghost, destructiveGhost
}

struct HypertimeButtonStyle: ButtonStyle {
    var kind: HypertimeButtonKind = .secondary
    var isFocused: Bool = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tokens.Typography.heading)
            .foregroundStyle(foreground)
            .padding(.horizontal, Tokens.Space.s3)
            .frame(height: Tokens.Size.buttonHeight)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.button, style: .continuous)
                    .fill(background)
            }
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: Tokens.Radius.button, style: .continuous)
                        .strokeBorder(Tokens.Palette.separator.color,
                                      lineWidth: Tokens.Focus.hairlineWidth(contrast == .increased))
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .focusRing(isFocused, radius: Tokens.Radius.button)
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.button, style: .continuous))
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Tokens.Palette.onAccent.color
        case .secondary: return Tokens.Palette.textPrimary.color
        case .ghost: return Tokens.Palette.textSecondary.color
        case .destructiveGhost: return Tokens.Palette.destructive.color
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Tokens.Palette.accent
        case .secondary: return Tokens.Palette.fieldBackground.color
        case .ghost, .destructiveGhost: return .clear
        }
    }
}

extension View {
    func hypertimeButton(_ kind: HypertimeButtonKind, isFocused: Bool = false) -> some View {
        buttonStyle(HypertimeButtonStyle(kind: kind, isFocused: isFocused))
    }
}

/// Small ⌘⌫ / ↩ / esc chip shown next to a button label.
struct KeyboardHint: View {
    let text: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(text)
            .font(Tokens.Typography.keyboardHint)
            .foregroundStyle(Tokens.Palette.textTertiary.color)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.kbdHint, style: .continuous)
                    .fill(Tokens.Palette.rowHover.color)
                    .overlay {
                        RoundedRectangle(cornerRadius: Tokens.Radius.kbdHint, style: .continuous)
                            .strokeBorder(Tokens.Palette.separator.color,
                                          lineWidth: Tokens.Focus.hairlineWidth(contrast == .increased))
                    }
            }
    }
}

// MARK: - Invalid shake

/// 2-cycle horizontal shake (300 ms) used for invalid input; never a modal.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(animatableData * .pi * 4), y: 0))
    }
}

extension View {
    func shake(_ trigger: Int, enabled: Bool = true) -> some View {
        modifier(ShakeModifier(trigger: trigger, enabled: enabled))
    }
}

private struct ShakeModifier: ViewModifier {
    let trigger: Int
    let enabled: Bool
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(animatableData: phase))
            .onChange(of: trigger) {
                guard enabled, !reduceMotion else { return }
                phase = 0
                withAnimation(Tokens.Motion.invalidShake.curve) { phase = 1 }
            }
    }
}

// MARK: - Separator

struct Hairline: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(Tokens.Palette.separator.color)
            .frame(height: Tokens.Focus.hairlineWidth(contrast == .increased))
    }
}

// MARK: - Scrolling list chrome

/// Fades the top and bottom edges of a scrollable list, per the "6 rows, scrolled" artboard.
struct EdgeFade: ViewModifier {
    var top: Bool
    var bottom: Bool

    func body(content: Content) -> some View {
        content.mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: top ? Tokens.Space.s3 : 0)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: bottom ? Tokens.Space.s3 : 0)
            }
        }
    }
}

extension View {
    func edgeFade(top: Bool, bottom: Bool) -> some View {
        modifier(EdgeFade(top: top, bottom: bottom))
    }
}

/// 3 pt overlay scroll indicator (the system one is thicker than the design allows).
struct ThinScrollIndicator: View {
    let contentHeight: CGFloat
    let visibleHeight: CGFloat
    let offset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let ratio = min(max(visibleHeight / max(contentHeight, 1), 0), 1)
            let thumb = max(proxy.size.height * ratio, 18)
            let travel = proxy.size.height - thumb
            let progress = contentHeight > visibleHeight ? min(max(offset / (contentHeight - visibleHeight), 0), 1) : 0
            if ratio < 1 {
                Capsule()
                    .fill(Tokens.Palette.textTertiary.color)
                    .frame(width: 3, height: thumb)
                    .offset(x: proxy.size.width - 3, y: travel * progress)
            }
        }
        .allowsHitTesting(false)
    }
}
