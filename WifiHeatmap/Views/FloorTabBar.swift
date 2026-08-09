import SwiftUI

struct FloorTabBar: View {
    @ObservedObject var document: WifiSurveyDocument
    @Binding var selectedFloorID: UUID?
    @Binding var showInspector: Bool

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach($document.survey.floors) { $floor in
                        FloorTabItem(
                            floor: $floor,
                            isSelected: floor.id == selectedFloorID,
                            onSelect: { selectedFloorID = floor.id },
                            onDelete: { deleteFloor(id: floor.id) }
                        )
                        Divider().frame(maxHeight: 20)
                    }
                    // + sits inside the scroll area, flush against the last tab
                    Button {
                        document.addFloor(name: "Floor \(document.survey.floors.count + 1)")
                        selectedFloorID = document.survey.floors.last?.id
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 32, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Add floor")
                }
                .frame(height: 36)
            }

            Spacer()

            Divider().frame(maxHeight: 20)

            Button {
                showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(showInspector ? .primary : .secondary)
            .help(showInspector ? "Hide inspector" : "Show inspector")
        }
        .frame(height: 36)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func deleteFloor(id: UUID) {
        document.survey.floors.removeAll { $0.id == id }
        if selectedFloorID == id {
            selectedFloorID = document.survey.floors.first?.id
        }
    }
}

struct FloorTabItem: View {
    @Binding var floor: Floor
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editName = ""
    @FocusState private var textFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isEditing {
                TextField("", text: $editName)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 50, maxWidth: 140)
                    .focused($textFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { isEditing = false }
            } else {
                Text(floor.name)
                    .lineLimit(1)
                    .frame(minWidth: 40, maxWidth: 140, alignment: .leading)
            }

            if isSelected && !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove floor")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .help("Click to switch to this floor. Right-click to rename or delete it.")
        .contextMenu {
            Button("Rename") { startEditing() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func startEditing() {
        onSelect()
        editName = floor.name
        isEditing = true
        textFocused = true
    }

    private func commitRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { floor.name = trimmed }
        isEditing = false
    }
}
