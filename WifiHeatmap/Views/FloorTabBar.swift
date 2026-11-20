import SwiftUI

struct FloorTabBar: View {
    @ObservedObject var document: WifiSurveyDocument
    @Binding var selectedFloorID: UUID?
    @Binding var showInspector: Bool

    @State private var floorPendingDeletion: Floor?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach($document.survey.floors) { $floor in
                        FloorTabItem(
                            floor: $floor,
                            isSelected: floor.id == selectedFloorID,
                            onSelect: { selectedFloorID = floor.id },
                            onDelete: { floorPendingDeletion = floor }
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
        .confirmationDialog(
            "Delete Floor?",
            isPresented: Binding(
                get: { floorPendingDeletion != nil },
                set: { if !$0 { floorPendingDeletion = nil } }
            ),
            presenting: floorPendingDeletion
        ) { floor in
            Button("Delete Floor", role: .destructive) {
                deleteFloor(id: floor.id)
                floorPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                floorPendingDeletion = nil
            }
        } message: { floor in
            Text("Delete \u{201c}\(floor.name)\u{201d} and all of its recorded survey data? This cannot be undone.")
        }
    }

    private func deleteFloor(id: UUID) {
        document.removeFloor(id: id)
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
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove floor")
                .accessibilityLabel("Delete \(floor.name)")
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
