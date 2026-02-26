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

    private let accentColor = Color.jarvisCyan

    var body: some View {
        Button(action: {
            WidgetActionHandler.shared.execute(widget: widget)
        }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: JarvisDimension.iconCircleSize, height: JarvisDimension.iconCircleSize)

                    Image(systemName: widget.icon ?? "link")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.label)
                        .font(JarvisFont.body)
                        .foregroundStyle(Color.jarvisTextPrimary)

                    if let url = widget.action.url {
                        Text(formatURL(url))
                            .font(JarvisFont.captionMono)
                            .foregroundStyle(Color.jarvisTextDim)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(isHovered ? 1.0 : 0.6))
                    .rotationEffect(.degrees(isHovered ? 0 : -5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(widgetBackground(color: accentColor, isHovered: isHovered))
            .overlay(widgetBorder(color: accentColor, isHovered: isHovered))
            .cornerRadius(JarvisRadius.large)
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

    private let accentColor = Color.jarvisGreen

    var body: some View {
        Button(action: {
            WidgetActionHandler.shared.execute(widget: widget)
        }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: JarvisRadius.medium)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: JarvisDimension.iconCircleSize, height: JarvisDimension.iconCircleSize)

                    Image(systemName: widget.icon ?? "app.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.label)
                        .font(JarvisFont.body)
                        .foregroundStyle(Color.jarvisTextPrimary)

                    if let appName = widget.action.appName {
                        Text(appName)
                            .font(JarvisFont.captionMono)
                            .foregroundStyle(Color.jarvisTextDim)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)
                        .opacity(isHovered ? 1.0 : 0.6)

                    Text("LAUNCH")
                        .font(JarvisFont.tag)
                        .foregroundStyle(accentColor.opacity(isHovered ? 1.0 : 0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(widgetBackground(color: accentColor, isHovered: isHovered))
            .overlay(widgetBorder(color: accentColor, isHovered: isHovered))
            .cornerRadius(JarvisRadius.large)
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

    private let accentColor = Color.jarvisPurple

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: JarvisRadius.large)
                    .fill(Color.black.opacity(0.3))
                    .frame(height: isExpanded ? 300 : 150)

                if let image = loadedImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: isExpanded ? .fit : .fill)
                        .frame(height: isExpanded ? 300 : 150)
                        .clipped()
                        .cornerRadius(JarvisRadius.large)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: JarvisRadius.large).stroke(accentColor.opacity(0.3), lineWidth: 1))
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }

            HStack {
                if let alt = widget.action.imageAlt {
                    Text(alt)
                        .font(JarvisFont.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                Spacer()
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                        Text(isExpanded ? "Collapse" : "Expand")
                            .font(JarvisFont.captionMono)
                    }
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, JarvisSpacing.sm)
                    .padding(.vertical, JarvisSpacing.xs)
                    .background(accentColor.opacity(0.15))
                    .cornerRadius(JarvisRadius.small)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: JarvisRadius.card).fill(Color.jarvisSurfaceDark))
        .overlay(RoundedRectangle(cornerRadius: JarvisRadius.card).stroke(accentColor.opacity(0.2), lineWidth: 1))
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

    private let accentColor = Color.jarvisAmber

    var body: some View {
        Button(action: {
            WidgetActionHandler.shared.execute(widget: widget)
        }) {
            HStack(spacing: JarvisSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: JarvisRadius.medium)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 40, height: 48)

                    VStack(spacing: 2) {
                        Image(systemName: fileIcon)
                            .font(.system(size: 18))
                            .foregroundStyle(accentColor)

                        if let ext = widget.action.fileType {
                            Text(ext.uppercased())
                                .font(JarvisFont.tag)
                                .foregroundStyle(accentColor.opacity(0.8))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: JarvisSpacing.xs) {
                    Text(widget.action.fileName ?? widget.label)
                        .font(JarvisFont.body)
                        .foregroundStyle(Color.jarvisTextPrimary)
                        .lineLimit(1)

                    if let path = widget.action.filePath {
                        Text(shortenPath(path))
                            .font(JarvisFont.captionMono)
                            .foregroundStyle(Color.jarvisTextDim)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(spacing: 2) {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                    Text("PREVIEW")
                        .font(JarvisFont.tag)
                }
                .foregroundStyle(accentColor.opacity(isHovered ? 1.0 : 0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(widgetBackground(color: accentColor, isHovered: isHovered))
            .overlay(widgetBorder(color: accentColor, isHovered: isHovered))
            .cornerRadius(JarvisRadius.large)
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

    private let accentColor = Color.jarvisCyan

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = widget.action.language {
                    Text(lang.uppercased())
                        .font(JarvisFont.tag)
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, JarvisSpacing.sm)
                        .padding(.vertical, JarvisSpacing.xs)
                        .background(accentColor.opacity(0.15))
                        .cornerRadius(JarvisRadius.small)
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
                    .foregroundStyle(showCopiedFeedback ? Color.jarvisGreen : accentColor)
                    .padding(.horizontal, JarvisSpacing.sm)
                    .padding(.vertical, JarvisSpacing.xs)
                    .background((showCopiedFeedback ? Color.jarvisGreen : accentColor).opacity(0.15))
                    .cornerRadius(JarvisRadius.small)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(widget.action.code ?? "")
                    .font(JarvisFont.code)
                    .foregroundStyle(Color.jarvisTextPrimary.opacity(0.9))
                    .padding(JarvisSpacing.md)
            }
            .frame(maxHeight: 200)
        }
        .background(Color.jarvisSurfaceDeep)
        .cornerRadius(JarvisRadius.large)
        .overlay(RoundedRectangle(cornerRadius: JarvisRadius.large).stroke(accentColor.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Confirmation Widget
struct ConfirmationWidgetView: View {
    let widget: ChatWidgetData
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    @State private var confirmHovered = false
    @State private var cancelHovered = false

    private let confirmColor = Color.jarvisGreen
    private let cancelColor = Color.jarvisRed

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.md) {
            Text(widget.label)
                .font(JarvisFont.body)
                .foregroundStyle(Color.jarvisTextPrimary)

            HStack(spacing: JarvisSpacing.md) {
                Button(action: { onConfirm?() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text(widget.action.confirmAction ?? "Confirm")
                            .font(JarvisFont.label)
                    }
                    .foregroundStyle(confirmHovered ? .black : confirmColor)
                    .padding(.horizontal, JarvisSpacing.lg)
                    .padding(.vertical, JarvisSpacing.sm)
                    .background(RoundedRectangle(cornerRadius: JarvisRadius.medium).fill(confirmHovered ? confirmColor : confirmColor.opacity(0.15)))
                    .overlay(RoundedRectangle(cornerRadius: JarvisRadius.medium).stroke(confirmColor.opacity(0.5), lineWidth: 1))
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
                            .font(JarvisFont.label)
                    }
                    .foregroundStyle(cancelHovered ? Color.jarvisTextPrimary : cancelColor.opacity(0.8))
                    .padding(.horizontal, JarvisSpacing.lg)
                    .padding(.vertical, JarvisSpacing.sm)
                    .background(RoundedRectangle(cornerRadius: JarvisRadius.medium).fill(cancelHovered ? cancelColor.opacity(0.3) : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: JarvisRadius.medium).stroke(cancelColor.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { cancelHovered = hovering }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: JarvisRadius.large).fill(Color.jarvisSurfaceDark))
        .overlay(RoundedRectangle(cornerRadius: JarvisRadius.large).stroke(Color.jarvisBorder, lineWidth: 1))
    }
}

// MARK: - Quick Action Widget
struct QuickActionWidgetView: View {
    let widget: ChatWidgetData
    @Binding var isHovered: Bool
    @Binding var isPressed: Bool

    private let accentColor = Color.jarvisCyan

    var body: some View {
        Button(action: {
            WidgetActionHandler.shared.execute(widget: widget)
        }) {
            HStack(spacing: JarvisSpacing.sm) {
                if let icon = widget.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(widget.label)
                    .font(JarvisFont.label)

                if let subtitle = widget.subtitle {
                    Spacer()
                    Text(subtitle)
                        .font(JarvisFont.captionMono)
                        .foregroundStyle(Color.jarvisTextDim)
                }
            }
            .foregroundStyle(isHovered ? .black : accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, JarvisSpacing.sm)
            .background(RoundedRectangle(cornerRadius: JarvisRadius.medium).fill(isHovered ? accentColor : accentColor.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: JarvisRadius.medium).stroke(accentColor.opacity(0.5), lineWidth: 1))
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
    RoundedRectangle(cornerRadius: JarvisRadius.large)
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
    RoundedRectangle(cornerRadius: JarvisRadius.large)
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

