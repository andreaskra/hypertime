import SwiftUI

/// The popup's own way into Reports and Settings, in the app's style rather than a system menu
/// — the status item's menu was the only route before, which is not where anyone looks.
struct OverflowMenuView: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let isDestructive: Bool
        let action: () -> Void

        init(_ title: String, symbol: String, isDestructive: Bool = false, action: @escaping () -> Void) {
            self.title = title
            self.symbol = symbol
            self.isDestructive = isDestructive
            self.action = action
        }
    }

    let groups: [[Item]]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Hairline().padding(.vertical, 2) }
                ForEach(group) { item in
                    MenuRow(item: item)
                }
            }
        }
        .padding(Tokens.Space.s2)
        .frame(width: 190)
    }
}

private struct MenuRow: View {
    let item: OverflowMenuView.Item
    @State private var isHovering = false

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: Tokens.Space.s2) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14)
                Text(item.title)
                    .font(Tokens.Typography.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(item.isDestructive
                             ? Tokens.Palette.destructive.color
                             : Tokens.Palette.textPrimary.color)
            .padding(.horizontal, Tokens.Space.s2)
            .frame(height: Tokens.Size.listRowHeight)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                    .fill(isHovering ? Tokens.Palette.rowHover.color : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
