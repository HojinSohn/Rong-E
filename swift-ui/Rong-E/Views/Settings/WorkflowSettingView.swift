import SwiftUI

struct WorkflowSettingsView: View {
    @StateObject var manager = WorkflowManager.shared
    @State private var newTaskInput = ""

    @EnvironmentObject var coordinator: WindowCoordinator
    
    // Pass the ID so we can close this specific window
    let windowID: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.lg) {
            HStack {
                Text("Startup Protocol")
                    .font(JarvisFont.title)
                    .foregroundStyle(Color.jarvisTextPrimary)
                Spacer()
                Button(action: {
                    coordinator.closeWindow(id: windowID)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.jarvisTextDim)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            
            Text("Tasks to run automatically when connected.")
                .font(JarvisFont.caption)
                .foregroundStyle(Color.jarvisTextDim)
            
            // Task List
            List {
                ForEach(manager.tasks) { task in
                    HStack(spacing: JarvisSpacing.md) {
                        // Drag handle
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(Color.jarvisTextDim)
                            .font(JarvisFont.caption)

                        Toggle("", isOn: Binding(
                            get: { task.isEnabled },
                            set: { _ in manager.toggle(task) }
                        ))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: Color.jarvisBlue))

                        Text(task.prompt)
                            .foregroundStyle(task.isEnabled ? Color.jarvisTextPrimary : Color.jarvisTextDim)
                            .strikethrough(!task.isEnabled)
                            .lineLimit(2)

                        Spacer()

                        // Delete button
                        Button(action: {
                            if let index = manager.tasks.firstIndex(where: { $0.id == task.id }) {
                                manager.delete(at: IndexSet(integer: index))
                            }
                        }) {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.jarvisRed.opacity(0.7))
                                .font(JarvisFont.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Color.jarvisSurfaceLight)
                }
                .onDelete(perform: manager.delete)
                .onMove(perform: manager.move)
            }
            .frame(height: 200)
            .scrollContentBackground(.hidden)
            .background(Color.jarvisSurfaceDark)
            .cornerRadius(JarvisRadius.medium)
            
            // Add New Task
            HStack {
                TextField("e.g. 'Check weather in West Lafayette'", text: $newTaskInput)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(JarvisFont.mono)
                    .padding(JarvisSpacing.sm)
                    .background(Color.jarvisSurfaceDeep)
                    .cornerRadius(JarvisRadius.small)
                    .overlay(RoundedRectangle(cornerRadius: JarvisRadius.small).stroke(Color.jarvisBorder, lineWidth: 1))
                    .foregroundStyle(Color.jarvisTextPrimary)
                    .onSubmit { addNew() }
                
                Button(action: addNew) {
                    Image(systemName: "plus")
                        .padding(JarvisSpacing.sm)
                        .background(Color.jarvisBlue)
                        .clipShape(Circle())
                        .foregroundStyle(Color.jarvisTextPrimary)
                }
                .buttonStyle(.plain)
                .disabled(newTaskInput.isEmpty)
            }
        }
        .padding()
        .background(Color.jarvisSurface)
        .cornerRadius(JarvisRadius.large)
        .frame(width: 400, height: 350)
        .onAppear {
            manager.loadTasks()
        }
    }
    
    func addNew() {
        guard !newTaskInput.isEmpty else { return }
        manager.addTask(newTaskInput)
        newTaskInput = ""
    }
}