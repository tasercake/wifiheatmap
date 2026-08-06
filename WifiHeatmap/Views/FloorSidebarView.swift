import SwiftUI

struct FloorSidebarView: View {
    @ObservedObject var document: WifiSurveyDocument
    @Binding var selectedFloorID: UUID?

    @State private var editingFloorID: UUID? = nil
    @State private var editingName = ""

    var body: some View {
        List(selection: $selectedFloorID) {
            ForEach($document.survey.floors) { $floor in
                if editingFloorID == floor.id {
                    TextField("Name", text: $editingName, onCommit: {
                        floor.name = editingName
                        editingFloorID = nil
                    })
                } else {
                    Text(floor.name)
                        .tag(floor.id)
                        .contextMenu {
                            Button("Rename") {
                                editingName = floor.name
                                editingFloorID = floor.id
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                document.survey.floors.removeAll { $0.id == floor.id }
                                if selectedFloorID == floor.id { selectedFloorID = nil }
                            }
                        }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { document.addFloor(name: "New Floor") } label: {
                    Label("Add Floor", systemImage: "plus")
                }
            }
        }
        .onAppear {
            if selectedFloorID == nil { selectedFloorID = document.survey.floors.first?.id }
        }
    }
}
