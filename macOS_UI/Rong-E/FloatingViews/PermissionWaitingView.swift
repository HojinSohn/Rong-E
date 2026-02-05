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
                        .foregroundColor(.yellow)
                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)
                    
                    Text("Screen Recording Permission Required")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Instructions
                Text("Please grant permission in System Settings, then click 'Retry'")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Buttons
                HStack(spacing: 12) {
                    Button(action: onRetry) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("Retry")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onCancel) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                            Text("Continue Without Screenshot")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.6))
                        .cornerRadius(8)
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
