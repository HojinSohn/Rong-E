import SwiftUI

// MARK: - Permission Waiting Overlay
struct PermissionWaitingView: View {
    let onRetry: () -> Void
    let onCancel: () -> Void
    let windowID: String
    let size: CGSize
    
    @State private var pulseAnimation = false
    @EnvironmentObject var coordinator: WindowCoordinator
    @ObservedObject private var _theme = AppContext.shared
    
    var body: some View {
        let animationsOff = _theme.themeAnimationsDisabled
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                // Icon + Title
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.jarvisAmber.opacity(0.15))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "eye.trianglebadge.exclamationmark")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.jarvisAmber)
                            .scaleEffect(animationsOff ? 1.0 : (pulseAnimation ? 1.08 : 1.0))
                            .animation(animationsOff ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulseAnimation)
                    }
                    
                    Text("Screen Recording Permission")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.jarvisTextPrimary)
                    
                    Text("Rong-E needs screen capture access to use Vision mode.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Step-by-step instructions
                VStack(alignment: .leading, spacing: 6) {
                    PermissionStepRow(number: "1", text: "Open System Settings → Privacy & Security")
                    PermissionStepRow(number: "2", text: "Select Screen Recording from the sidebar")
                    PermissionStepRow(number: "3", text: "Toggle ON for Rong-E, then click Retry")
                }
                .padding(.horizontal, 8)
                
                // Action Buttons
                VStack(spacing: 8) {
                    // Primary: Open System Settings
                    Button(action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gear")
                                .font(.system(size: 11, weight: .medium))
                            Text("Open System Settings")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.jarvisAmber)
                        .cornerRadius(JarvisRadius.medium)
                    }
                    .buttonStyle(.plain)
                    
                    HStack(spacing: 8) {
                        // Retry button
                        Button(action: onRetry) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .medium))
                                Text("Retry")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(Color.jarvisTextPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.jarvisGreen.opacity(0.8))
                            .cornerRadius(JarvisRadius.medium)
                        }
                        .buttonStyle(.plain)
                        
                        // Skip button
                        Button(action: onCancel) {
                            HStack(spacing: 5) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 9))
                                Text("Skip")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(Color.jarvisTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(JarvisRadius.medium)
                            .overlay(
                                RoundedRectangle(cornerRadius: JarvisRadius.medium)
                                    .stroke(Color.jarvisTextDim.opacity(0.3), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: size.width, height: size.height)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: JarvisRadius.container)
                    .fill(Color.jarvisSurfaceDark)
                RoundedRectangle(cornerRadius: JarvisRadius.container)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.jarvisAmber.opacity(0.5), Color.jarvisAmber.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.5), radius: 20)
        .onAppear {
            pulseAnimation = true
        }
    }
}

// MARK: - Permission Step Row
private struct PermissionStepRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.jarvisAmber)
                .frame(width: 14, height: 14)
                .background(Color.jarvisAmber.opacity(0.15))
                .cornerRadius(3)
            
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.jarvisTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
