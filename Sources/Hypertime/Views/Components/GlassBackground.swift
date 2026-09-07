import AppKit
import SwiftUI

/// `NSVisualEffectView` for SwiftUI.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.isEmphasized = isEmphasized
        view.state = .active
    }
}

/// Forces glass surfaces to paint their opaque fallback. Used by `--screenshots`, where
/// window-server materials cannot be captured off-screen.
extension EnvironmentValues {
    @Entry var opaqueSurfaces: Bool = false
}

/// Glass surface from the handoff: material + tint + inner highlight stroke, with an automatic
/// solid fallback when Reduce Transparency is on (§7.2).
struct GlassBackground: View {
    let style: Tokens.MaterialStyle
    var cornerRadius: CGFloat = Tokens.Radius.panel
    /// Hairlines step up one level under Increase Contrast.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.opaqueSurfaces) private var opaqueSurfaces
    @Environment(\.colorSchemeContrast) private var contrast

    private var isOpaque: Bool { reduceTransparency || opaqueSurfaces }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(isOpaque ? AnyShapeStyle(style.fallback.color) : AnyShapeStyle(style.tint.color))
            .background {
                if !isOpaque {
                    VisualEffectView(material: style.material, blending: style.blending)
                        .clipShape(shape)
                }
            }
            .overlay {
                // Inner highlight: light at the top edge, shadowed at the bottom.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Tokens.Palette.strokeGlassTop.color, Tokens.Palette.strokeGlassBottom.color],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: contrast == .increased ? 1 : 0.5
                )
            }
    }
}

extension View {
    /// Paints a glass surface behind the view.
    func glass(_ style: Tokens.MaterialStyle, radius: CGFloat = Tokens.Radius.panel) -> some View {
        background { GlassBackground(style: style, cornerRadius: radius) }
    }
}
