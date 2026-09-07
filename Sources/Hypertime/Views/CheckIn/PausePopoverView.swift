import SwiftUI
import HypertimeCore

/// A-pause: 240 pt popover with duration chips and a custom field that uses the same parser
/// as the amount field.
struct PausePopoverView: View {
    let morningHour: Int
    let validate: (String) -> Seconds?
    let onPick: (PausePreset, Seconds?) -> Void

    @State private var customText = ""
    @State private var isInvalid = false
    @State private var shakeTrigger = 0

    private let presets: [PausePreset] = [.m15, .m30, .h1, .h2, .untilMorning]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("Pause tracking")
                .font(Tokens.Typography.heading)
                .foregroundStyle(Tokens.Palette.textSecondary.color)

            FlowChips(items: presets.map { ($0, $0.title(morningHour: morningHour)) }) { preset in
                onPick(preset, nil)
            }

            HStack(spacing: Tokens.Space.s2) {
                EditableField(
                    text: customText,
                    placeholder: "45m",
                    font: Tokens.Typography.body,
                    isInvalid: isInvalid,
                    isFocused: false,
                    onText: { customText = $0; isInvalid = false },
                    onCommand: { selector, _ in
                        guard selector == .insertNewline else { return false }
                        submitCustom()
                        return true
                    }
                )
                .frame(height: Tokens.Size.fieldHeight - 4)
                .padding(.horizontal, Tokens.Space.s2)
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.field, style: .continuous)
                        .fill(isInvalid ? Tokens.Palette.invalidFieldBackground.color : Tokens.Palette.fieldBackground.color)
                }
                .shake(shakeTrigger)

                Button("Pause") { submitCustom() }
                    .hypertimeButton(.primary)
            }

            Text(isInvalid ? "Try 45m, 1:30 or 2h" : "Custom duration · same formats as the amount field")
                .font(Tokens.Typography.caption)
                .foregroundStyle(isInvalid ? Tokens.Palette.invalid.color : Tokens.Palette.textTertiary.color)
        }
        .padding(Tokens.Space.s4)
        .frame(width: Tokens.Size.pausePopoverWidth)
    }

    private func submitCustom() {
        guard let seconds = validate(customText), seconds > 0 else {
            isInvalid = true
            shakeTrigger += 1
            return
        }
        onPick(.custom, seconds)
    }
}

/// Wrapping row of chips.
private struct FlowChips: View {
    let items: [(PausePreset, String)]
    let onTap: (PausePreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Tokens.Space.s2) {
                    ForEach(row, id: \.0) { item in
                        Button(item.1) { onTap(item.0) }
                            .buttonStyle(ChipStyle())
                    }
                }
            }
        }
    }

    /// Two chips per row keeps the 240 pt popover tidy; the "Until 07:00" chip takes its own row.
    private var rows: [[(PausePreset, String)]] {
        var result: [[(PausePreset, String)]] = []
        var current: [(PausePreset, String)] = []
        for item in items {
            if item.0 == .untilMorning {
                if !current.isEmpty { result.append(current); current = [] }
                result.append([item])
            } else {
                current.append(item)
                if current.count == 2 { result.append(current); current = [] }
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

private struct ChipStyle: ButtonStyle {
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tokens.Typography.body)
            .foregroundStyle(Tokens.Palette.textPrimary.color)
            .padding(.horizontal, Tokens.Space.s3)
            .frame(height: 24)
            .background {
                Capsule().fill(Tokens.Palette.fieldBackground.color)
                    .overlay {
                        Capsule().strokeBorder(Tokens.Palette.separator.color,
                                               lineWidth: Tokens.Focus.hairlineWidth(contrast == .increased))
                    }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
