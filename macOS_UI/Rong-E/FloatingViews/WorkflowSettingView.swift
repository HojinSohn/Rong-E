import SwiftUI

struct WorkflowSettingsView: View {
    @StateObject var manager = WorkflowManager()
    @State private var newTaskInput = ""

    @EnvironmentObject var coordinator: WindowCoordinator
    
    // Pass the ID so we can close this specific window
    let windowID: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Startup Protocol")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    coordinator.closeWindow(id: windowID)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            
            Text("Tasks to run automatically when connected.")
                .font(.caption)
                .foregroundColor(.gray)
            
            // Task List
            List {
                ForEach(manager.tasks) { task in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { task.isEnabled },
                            set: { _ in manager.toggle(task) }
                        ))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        
                        Text(task.prompt)
                            .foregroundColor(task.isEnabled ? .white : .gray)
                            .strikethrough(!task.isEnabled)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                .onDelete(perform: manager.delete)
            }
            .frame(height: 200)
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            
            // Add New Task
            HStack {
                TextField("e.g. 'Check weather in West Lafayette'", text: $newTaskInput)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .foregroundColor(.white)
                    .onSubmit { addNew() } // Press Enter to add
                
                Button(action: addNew) {
                    Image(systemName: "plus")
                        .padding(8)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(newTaskInput.isEmpty)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
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