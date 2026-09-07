import SwiftUI

/// The filtering dropdown (R-05, R-07). Overlays everything below the project field while open.
struct ProjectList: View {
    @Bindable var viewModel: CheckInViewModel

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
            }
            .onChange(of: viewModel.highlighted) {
                if let row = viewModel.highlightedRow { proxy.scrollTo(row.id) }
            }
        }
        .frame(maxHeight: 150)
        .background(.regularMaterial)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func rowView(_ row: ProjectMatchRow, isHighlighted: Bool) -> some View {
        HStack(spacing: 6) {
            switch row {
            case .create(let name):
                Image(systemName: "plus.circle")
                Text("Create “\(name)”")
            case .project(let project, let indices):
                highlightedName(project.name, indices: indices)
                if project.id == viewModel.currentProjectID {
                    Text("current")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isHighlighted ? Color.accentColor.opacity(0.25) : Color.clear)
    }

    /// Matched characters are emphasised so the fuzzy match is visible.
    private func highlightedName(_ name: String, indices: [Int]) -> Text {
        let set = Set(indices)
        return name.enumerated().reduce(Text("")) { partial, pair in
            let character = Text(String(pair.element))
            return partial + (set.contains(pair.offset) ? character.bold() : character.foregroundStyle(.primary))
        }
    }
}
