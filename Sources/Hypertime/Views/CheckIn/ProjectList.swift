import SwiftUI

/// The filtering dropdown (R-05, R-07). Popover material, overlays and dims the today list;
/// never shows times — that is the today list's job (HANDOFF "Dropdown vs today list").
struct ProjectList: View {
    @Bindable var viewModel: CheckInViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.matches.enumerated()), id: \.element.id) { index, row in
                        rowView(row, isHighlighted: index == viewModel.highlighted)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectRow(index)
                                viewModel.commit()
                            }
                    }
                }
                .padding(Tokens.Space.s1)
            }
            .onChange(of: viewModel.highlighted) {
                withAnimation(Tokens.Motion.highlightMove.animation(reduceMotion: reduceMotion)) {
                    if let row = viewModel.highlightedRow { proxy.scrollTo(row.id) }
                }
            }
        }
        .frame(height: height)
        .glass(Tokens.Materials.popover, radius: Tokens.Radius.field)
        .shadow(Tokens.Shadows.popover, scheme)
    }

    /// Rows are 26 pt; at most six are visible before the list scrolls.
    var height: CGFloat {
        let rows = min(viewModel.matches.count, Tokens.Size.todayListMaxVisibleRows)
        return CGFloat(rows) * Tokens.Size.dropdownRowHeight + Tokens.Space.s2
    }

    @ViewBuilder
    private func rowView(_ row: ProjectMatchRow, isHighlighted: Bool) -> some View {
        HStack(spacing: Tokens.Space.s2) {
            switch row {
            case .create(let name):
                Image(systemName: Tokens.Icons.addProject)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Tokens.Palette.accent)
                Text("Create “\(name)”")
                    .font(Tokens.Typography.listRowCurrent)
                    .foregroundStyle(Tokens.Palette.accent)
                    .lineLimit(1)
                Spacer(minLength: Tokens.Space.s2)
                Text("NEW")
                    .font(Tokens.Typography.keyboardHint)
                    .foregroundStyle(Tokens.Palette.onAccent.color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Tokens.Palette.accent))
            case .project(let project, let indices):
                highlightedName(project.name, indices: indices)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if project.id == viewModel.currentProjectID {
                    Circle()
                        .fill(Tokens.Palette.trackingIndicator.color)
                        .frame(width: Tokens.Size.indicatorDot, height: Tokens.Size.indicatorDot)
                }
            }
        }
        .padding(.horizontal, Tokens.Space.s2)
        .frame(height: Tokens.Size.dropdownRowHeight)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                .fill(isHighlighted ? Tokens.Palette.rowSelected(scheme) : .clear)
        }
    }

    /// Matched characters are accent-bold so the fuzzy match is visible.
    private func highlightedName(_ name: String, indices: [Int]) -> Text {
        let set = Set(indices)
        return name.enumerated().reduce(Text("")) { partial, pair in
            let character = Text(String(pair.element))
            if set.contains(pair.offset) {
                return partial + character
                    .font(Tokens.Typography.listRowCurrent.font.weight(.semibold))
                    .foregroundColor(Tokens.Palette.accent)
            }
            return partial + character
                .font(Tokens.Typography.listRow.font)
                .foregroundColor(Tokens.Palette.textPrimary.color)
        }
    }
}
