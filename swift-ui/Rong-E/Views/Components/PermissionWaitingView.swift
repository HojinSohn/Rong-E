import SwiftUI

// MARK: - Permission Waiting Overlay
struct PermissionWaitingView: View {
    let onRetry: () -> Void
    let onCancel: () -> Void
    let windowID: String
    let size: CGSize
    
    @State private var pulseAnimation = false
    @EnvironmentObject var coordinator: WindowCoordinator
    
    var body: some View {
        VStack(spacing: 0) {
            // Banner
            VStack(spacing: 12) {
                // Icon + Title
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.jarvisAmber)
                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)
                    
                    Text("Screen Recording Permission Required")
                        .font(JarvisFont.body)
                        .foregroundStyle(Color.jarvisTextPrimary)
                }
                
                // Instructions
                Text("Please grant permission in System Settings, then click 'Retry'")
                    .font(JarvisFont.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Buttons
                HStack(spacing: JarvisSpacing.md) {
                    Button(action: onRetry) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("Retry")
                                .font(JarvisFont.label)
                        }
                        .foregroundStyle(Color.jarvisTextPrimary)
                        .padding(.horizontal, JarvisSpacing.lg)
                        .padding(.vertical, JarvisSpacing.sm)
                        .background(Color.jarvisGreen.opacity(0.8))
                        .cornerRadius(JarvisRadius.medium)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onCancel) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                            Text("Continue Without Screenshot")
                                .font(JarvisFont.label)
                        }
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .padding(.horizontal, JarvisSpacing.lg)
                        .padding(.vertical, JarvisSpacing.sm)
                        .background(Color.jarvisDim.opacity(0.6))
                        .cornerRadius(JarvisRadius.medium)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .shadow(color: .black.opacity(0.6), radius: 20)
            
            Spacer()
        }
        .padding(.top, 20)
        .frame(width: size.width, height: size.height)
        .background(Color.black.opacity(0.4))
        .onAppear {
            pulseAnimation = true
        }
    }
}
