import Foundation
import Combine

struct WorkflowTask: Identifiable, Codable, Hashable {
    var id = UUID()
    var prompt: String
    var isEnabled: Bool = true
    var order: Int
}

class WorkflowManager: ObservableObject {
    @Published var tasks: [WorkflowTask] = []
    
    private let key = "StartupWorkflowTasks"
    
    init() {
        loadTasks()
    }
    
    // --- CRUD Operations ---
    
    func loadTasks() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([WorkflowTask].self, from: data) {
            self.tasks = decoded.sorted { $0.order < $1.order }
        } else {
            // Default "Demo" Tasks
            self.tasks = [
                WorkflowTask(prompt: "Check my calendar for meetings today.", isEnabled: true, order: 0),
                WorkflowTask(prompt: "Check unread emails from 'Honeywell'.", isEnabled: true, order: 1),
                WorkflowTask(prompt: "Search online for 'AI News today'.", isEnabled: false, order: 2)
            ]
        }
    }
    
    func saveTasks() {
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    func addTask(_ prompt: String) {
        let nextOrder = (tasks.last?.order ?? -1) + 1
        let task = WorkflowTask(prompt: prompt, isEnabled: true, order: nextOrder)
        tasks.append(task)
        saveTasks()
    }
    
    func toggle(_ task: WorkflowTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].isEnabled.toggle()
            saveTasks()
        }
    }
    
    func delete(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets)
        saveTasks()
    }
}