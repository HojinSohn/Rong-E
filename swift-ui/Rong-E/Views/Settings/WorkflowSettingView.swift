import SwiftUI

struct WorkflowSettingsView: View {
    @StateObject var manager = WorkflowManager.shared
    @State private var newTaskInput = ""
    @ObservedObject private var context = AppContext.shared
    @EnvironmentObject var coordinator: WindowCoordinator

    let windowID: String

    var body: some View {
        ZStack {
            // 1. Deep Background
            Color.black.ignoresSafeArea()

            // 2. Tech Grid & Blur
            TechGridBackground()
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(0.8)
                .ignoresSafeArea()

            // 3. Decorative HUD Corners
            VStack {
                HStack {
                    CornerBracket(topLeft: true)
                    Spacer()
                    CornerBracket(topLeft: false)
                }
                Spacer()
                HStack {
                    CornerBracket(topLeft: false, rotate: true)
                    Spacer()
                    CornerBracket(topLeft: true, rotate: true)
                }
            }
            .padding(10)
            .allowsHitTesting(false)

            // 4. Content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Circle()
                        .fill(context.themeAccentColor)
                        .frame(width: 8, height: 8)
                        .modifier(JarvisGlow(active: true))

                    Text("SYSTEM // STARTUP_PROTOCOL")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(context.themeAccentColor)
                        .tracking(2)

                    Spacer()

                    // Status Badge
                    HStack(spacing: 6) {
                        Text("TASKS:")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.jarvisTextDim)
                        Text("\(manager.tasks.filter { $0.isEnabled }.count)/\(manager.tasks.count) ACTIVE")
                            .font(.system(size: 10, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(manager.tasks.isEmpty ? .jarvisTextDim : .jarvisGreen)
                            .shadow(color: manager.tasks.isEmpty ? .clear : .jarvisGreen.opacity(0.8), radius: 5)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(
                        (manager.tasks.isEmpty ? Color.jarvisTextDim : Color.jarvisGreen).opacity(0.3), lineWidth: 1
                    ))

                    Spacer().frame(width: 10)

                    Button(action: { coordinator.closeWindow(id: windowID) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(context.themeAccentColor.opacity(0.8))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .background(context.themeAccentColor.opacity(0.05))
                .overlay(Rectangle().frame(height: 1).foregroundColor(context.themeAccentColor.opacity(0.3)), alignment: .bottom)

                // Main Content — task list scrolls, add section stays pinned at bottom
                VStack(spacing: 0) {
                    // Scrollable task list
                    taskListSection
                        .padding(20)

                    // Pinned bottom section
                    VStack(alignment: .leading, spacing: 0) {
                        // Section Divider
                        HStack {
                            Rectangle().frame(height: 1).foregroundColor(context.themeAccentColor.opacity(0.3))
                            Text("NEW TASK")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(context.themeAccentColor.opacity(0.7))
                            Rectangle().frame(height: 1).foregroundColor(context.themeAccentColor.opacity(0.3))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)

                        // Add Task Section
                        addTaskSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    }
                    .background(context.themeAccentColor.opacity(0.03))
                }
            }
        }
        .frame(width: 500, height: 500)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(context.themeAccentColor.opacity(0.3), lineWidth: 1)
        )
        .preferredColorScheme(.dark)
        .onAppear {
            manager.loadTasks()
        }
    }

    // MARK: - Task List Section
    private var taskListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONFIGURED TASKS")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(context.themeAccentColor.opacity(0.7))
                .tracking(1)

            Text("These tasks run automatically each time Rong-E connects. Toggle to enable or disable.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.jarvisTextDim)
                .fixedSize(horizontal: false, vertical: true)

            if manager.tasks.isEmpty {
                // Empty state
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 24))
                            .foregroundColor(.jarvisTextDim.opacity(0.4))
                        Text("NO TASKS CONFIGURED")
                            .font(.system(size: 11, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.jarvisTextDim)
                        Text("Add a task below to automate your startup workflow")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.jarvisTextDim.opacity(0.6))
                    }
                    .padding(.vertical, 25)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(manager.tasks.enumerated()), id: \.element.id) { index, task in
                            WorkflowTaskRow(
                                task: task,
                                index: index + 1,
                                accentColor: context.themeAccentColor,
                                onToggle: { manager.toggle(task) },
                                onDelete: {
                                    if let idx = manager.tasks.firstIndex(where: { $0.id == task.id }) {
                                        manager.delete(at: IndexSet(integer: idx))
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .modifier(JarvisPanel())
    }

    // MARK: - Add Task Section
    private var addTaskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADD STARTUP TASK")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(context.themeAccentColor.opacity(0.7))
                .tracking(1)

            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 12))
                    .foregroundColor(.jarvisTextDim)

                TextField("e.g. Check my calendar for today's meetings", text: $newTaskInput)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .font(.system(size: 12, design: .monospaced))
                    .background(Color.black.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(
                        newTaskInput.isEmpty ? context.themeAccentColor.opacity(0.5) : context.themeAccentColor,
                        lineWidth: 1
                    ))
                    .foregroundColor(.jarvisTextPrimary)
                    .onSubmit { addNew() }
            }

            HStack {
                Spacer()
                Button(action: addNew) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("ADD TASK")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(context.themeAccentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(context.themeAccentColor.opacity(0.2))
                    .overlay(Rectangle().stroke(context.themeAccentColor, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(newTaskInput.isEmpty)
                .opacity(newTaskInput.isEmpty ? 0.4 : 1.0)
            }
        }
        .modifier(JarvisPanel())
    }

    func addNew() {
        guard !newTaskInput.isEmpty else { return }
        manager.addTask(newTaskInput)
        newTaskInput = ""
    }
}

// MARK: - Workflow Task Row
private struct WorkflowTaskRow: View {
    let task: WorkflowTask
    let index: Int
    let accentColor: Color
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Order number
            Text("\(String(format: "%02d", index))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(task.isEnabled ? accentColor.opacity(0.8) : .jarvisTextDim.opacity(0.4))
                .frame(width: 20)

            // Toggle button
            Button(action: onToggle) {
                Image(systemName: task.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(task.isEnabled ? .jarvisGreen : .jarvisTextDim.opacity(0.4))
            }
            .buttonStyle(BorderlessButtonStyle())

            // Task text
            VStack(alignment: .leading, spacing: 2) {
                Text(task.prompt)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(task.isEnabled ? .jarvisTextPrimary : .jarvisTextDim)
                    .strikethrough(!task.isEnabled, color: .jarvisTextDim.opacity(0.4))
                    .lineLimit(2)

                Text(task.isEnabled ? "ENABLED" : "DISABLED")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(task.isEnabled ? .jarvisGreen.opacity(0.7) : .jarvisTextDim.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Delete button
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.jarvisRed.opacity(0.8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(BorderlessButtonStyle())
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color.white.opacity(0.04) : Color.black.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isHovering ? accentColor.opacity(0.2) : accentColor.opacity(0.08), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}