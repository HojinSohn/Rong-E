import SwiftUI
import AppKit

// MARK: - Main Widget Container
struct ChatWidgetView: View {
    let widget: ChatWidgetData
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var showCopiedFeedback = false

    var body: some View {
        Group {
            switch widget.type {
            case "link":
                LinkWidgetView(widget: widget, isHovered: $isHovered, isPressed: $isPressed)
            case "app_launch":
                AppLaunchWidgetView(widget: widget, isHovered: $isHovered, isPressed: $isPressed)
            case "image":
                ImageWidgetView(widget: widget)
            case "file_preview":
                FilePreviewWidgetView(widget: widget, isHovered: $isHovered, isPressed: $isPressed)
            case "code_block":
                CodeBlockWidgetView(widget: widget, showCopiedFeedback: $showCopiedFeedback)
            case "confirmation":
                ConfirmationWidgetView(widget: widget, onConfirm: onConfirm, onCancel: onCancel)
            case "quick_action":
                QuickActionWidgetView(widget: widget, isHovered: $isHovered, isPressed: $isPressed)
            default:
                QuickActionWidgetView(widget: widget, isHovered: $isHovered, isPressed: $isPressed)
            }
        }
    }
}

// MARK: - Widget Action Handler
class WidgetActionHandler {
    static let shared = WidgetActionHandler()
    private init() {}

    func execute(widget: ChatWidgetData, completion: ((Bool) -> Void)? = nil) {
        switch widget.type {
        case "link":
            openLink(widget.action)
            completion?(true)
        case "app_launch":
            launchApp(widget.action, completion: completion)
        case "file_preview":
            previewFile(widget.action)
            completion?(true)
        case "code_block":
            copyCode(widget.action)
            completion?(true)
        default:
            completion?(true)
        }
    }

    private func openLink(_ action: WidgetActionData) {
        guard let urlString = action.url, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func launchApp(_ action: WidgetActionData, completion: ((Bool) -> Void)?) {
        if let bundleId = action.appBundleId,
           let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: appUrl, configuration: .init()) { _, error in
                completion?(error == nil)
            }
            return
        }

        if let schemeString = action.appScheme, let url = URL(string: schemeString) {
            NSWorkspace.shared.open(url)
            completion?(true)
            return
        }

        if let appName = action.appName {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", appName]
            do {
                try process.run()
                completion?(true)
            } catch {
                completion?(false)
            }
        }
    }

    private func previewFile(_ action: WidgetActionData) {
        guard let pathString = action.filePath else { return }
        let url = URL(fileURLWithPath: pathString)
        
        // Check if we can access the file before trying to open it
        if FileManager.default.isReadableFile(atPath: pathString) {
            // We have permission, try to open normally
            NSWorkspace.shared.open(url)
        } else {
            // No permission? Ask Finder to show it to the user instead.
            // This bypasses the sandbox "read" restriction because Finder does the work.
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func copyCode(_ action: WidgetActionData) {
        guard let code = action.code else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}

// MARK: - Link Widget
struct LinkWidgetView: View {
    let widget: ChatWidgetData
    @Binding var isHovered: Bool
    @Binding var isPressed: Bool

    private let hudCyan = Color(red: 0.0, green: 0.9, blue: 1.0)

    var body: some View {
        Button(action: {
            WidgetActionHandler.shared.execute(widget: widget)
        }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(hudCyan.opacity(0.15))
                        .frame(width: 32, height: 32)

                    Image(systemName: widget.icon ?? "link")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hudCyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)

                    if let url = widget.action.url {
                        Text(formatURL(url))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hudCyan.opacity(isHovered ? 1.0 : 0.6))
                    .rotationEffect(.degrees(isHovered ? 0 : -5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(widgetBackground(color: hudCyan, isHovered: isHovered))
            .overlay(widgetBorder(color: hudCyan, isHovered: isHovered))
            .cornerRadius(12)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }

    private func formatURL(_ url: String) -> String {
        let cleaned = url.replacingOccurrences(of: "https://", with: "")
                         .replacingOccurrences(of: "http://", with: "")
        return String(cleaned.prefix(40)) + (cleaned.count > 40 ? "..." : "")
    }
}

// MARK: - App Launch Widget
struct AppLaunchWidgetView: View {
    let widget: ChatWidgetData
    @Binding var isHovered: Bool
    @Binding var isPressed: Bool

    private let hudGreen = Color(red: 0.0, green: 1.0, blue: 0.6)

    var body: some View {
        Button(action: {
            WidgetActionHandler.shared.execute(widget: widget)
        }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hudGreen.opacity(0.15))
                        .frame(width: 32, height: 32)

                    Image(systemName: widget.icon ?? "app.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hudGreen)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)

                    if let appName = widget.action.appName {
                        Text(appName)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(hudGreen)
                        .frame(width: 6, height: 6)
                        .opacity(isHovered ? 1.0 : 0.6)

                    Text("LAUNCH")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(hudGreen.opacity(isHovered ? 1.0 : 0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(widgetBackground(color: hudGreen, isHovered: isHovered))
            .overlay(widgetBorder(color: hudGreen, isHovered: isHovered))
            .cornerRadius(12)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

// MARK: - Image Widget
struct ImageWidgetView: View {
    let widget: ChatWidgetData
    @State private var isExpanded = false
    @State private var loadedImage: NSImage?

    private let hudPurple = Color(red: 0.7, green: 0.4, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                    .frame(height: isExpanded ? 300 : 150)

                if let image = loadedImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: isExpanded ? .fit : .fill)
                        .frame(height: isExpanded ? 300 : 150)
                        .clipped()
                        .cornerRadius(12)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(hudPurple.opacity(0.3), lineWidth: 1))
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }

            HStack {
                if let alt = widget.action.imageAlt {
                    Text(alt)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                        Text(isExpanded ? "Collapse" : "Expand")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(hudPurple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(hudPurple.opacity(0.15))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.2)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(hudPurple.opacity(0.2), lineWidth: 1))
        .onAppear { loadImage() }
    }

    private func loadImage() {
        if let base64 = widget.action.base64Image,
           let data = Data(base64Encoded: base64),
           let image = NSImage(data: data) {
            loadedImage = image
        } else if let urlString = widget.action.imageUrl,
                  let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data, let image = NSImage(data: data) {
                    DispatchQueue.main.async { loadedImage = image }
                }
            }.resume()
        }
    }
}

// MARK: - File Preview Widget
struct FilePreviewWidgetView: View {
    let widget: ChatWidgetData
    @Binding var isHovered: Bool
    @Binding var isPressed: Bool

    private let hudAmber = Color(red: 1.0, green: 0.8, blue: 0.0)

    var body: some View {
        Button(action: {
            WidgetActionHandler.shared.execute(widget: widget)
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hudAmber.opacity(0.15))
                        .frame(width: 40, height: 48)

                    VStack(spacing: 2) {
                        Image(systemName: fileIcon)
                            .font(.system(size: 18))
                            .foregroundStyle(hudAmber)

                        if let ext = widget.action.fileType {
                            Text(ext.uppercased())
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(hudAmber.opacity(0.8))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(widget.action.fileName ?? widget.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let path = widget.action.filePath {
                        Text(shortenPath(path))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(spacing: 2) {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                    Text("PREVIEW")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(hudAmber.opacity(isHovered ? 1.0 : 0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(widgetBackground(color: hudAmber, isHovered: isHovered))
            .overlay(widgetBorder(color: hudAmber, isHovered: isHovered))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }

    private var fileIcon: String {
        guard let type = widget.action.fileType?.lowercased() else { return "doc" }
        switch type {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif": return "photo"
        case "mp4", "mov": return "film"
        case "mp3", "wav": return "waveform"
        case "swift", "py", "js", "ts": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count > 3 {
            return "~/.../" + components.suffix(2).joined(separator: "/")
        }
        return path
    }
}

// MARK: - Code Block Widget
struct CodeBlockWidgetView: View {
    let widget: ChatWidgetData
    @Binding var showCopiedFeedback: Bool

    private let hudCyan = Color(red: 0.0, green: 0.9, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = widget.action.language {
                    Text(lang.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(hudCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(hudCyan.opacity(0.15))
                        .cornerRadius(4)
                }

                Spacer()

                Button(action: {
                    WidgetActionHandler.shared.execute(widget: widget)
                    withAnimation { showCopiedFeedback = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showCopiedFeedback = false }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(showCopiedFeedback ? "Copied!" : "Copy")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(showCopiedFeedback ? .green : hudCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((showCopiedFeedback ? Color.green : hudCyan).opacity(0.15))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(widget.action.code ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(12)
            }
            .frame(maxHeight: 200)
        }
        .background(Color(white: 0.1))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(hudCyan.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Confirmation Widget
struct ConfirmationWidgetView: View {
    let widget: ChatWidgetData
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    @State private var confirmHovered = false
    @State private var cancelHovered = false

    private let hudGreen = Color(red: 0.0, green: 1.0, blue: 0.6)
    private let hudRed = Color(red: 1.0, green: 0.4, blue: 0.4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(widget.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Button(action: { onConfirm?() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text(widget.action.confirmAction ?? "Confirm")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(confirmHovered ? .black : hudGreen)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(confirmHovered ? hudGreen : hudGreen.opacity(0.15)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(hudGreen.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { confirmHovered = hovering }
                }

                Button(action: { onCancel?() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text(widget.action.cancelAction ?? "Cancel")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(cancelHovered ? .white : hudRed.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(cancelHovered ? hudRed.opacity(0.3) : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(hudRed.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { cancelHovered = hovering }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Quick Action Widget
struct QuickActionWidgetView: View {
    let widget: ChatWidgetData
    @Binding var isHovered: Bool
    @Binding var isPressed: Bool

    private let hudCyan = Color(red: 0.0, green: 0.9, blue: 1.0)

    var body: some View {
        Button(action: {
            WidgetActionHandler.shared.execute(widget: widget)
        }) {
            HStack(spacing: 8) {
                if let icon = widget.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(widget.label)
                    .font(.system(size: 12, weight: .medium))

                if let subtitle = widget.subtitle {
                    Spacer()
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .foregroundStyle(isHovered ? .black : hudCyan)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(isHovered ? hudCyan : hudCyan.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(hudCyan.opacity(0.5), lineWidth: 1))
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

// MARK: - Widget Container for Multiple Widgets
struct ChatWidgetsContainer: View {
    let widgets: [ChatWidgetData]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(widgets.enumerated()), id: \.offset) { _, widget in
                ChatWidgetView(widget: widget)
            }
        }
    }
}

// MARK: - Helper Views
private func widgetBackground(color: Color, isHovered: Bool) -> some View {
    RoundedRectangle(cornerRadius: 12)
        .fill(
            LinearGradient(
                colors: [
                    color.opacity(isHovered ? 0.15 : 0.08),
                    Color.black.opacity(0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .background(.ultraThinMaterial.opacity(0.3))
}

private func widgetBorder(color: Color, isHovered: Bool) -> some View {
    RoundedRectangle(cornerRadius: 12)
        .stroke(
            LinearGradient(
                colors: [
                    color.opacity(isHovered ? 0.8 : 0.4),
                    color.opacity(isHovered ? 0.4 : 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1
        )
}

