import SwiftUI

// MARK: - Smart Handoff Widget Logic
enum AgentActivity {
    case coding    // Agent is writing code
    case browsing  // Agent is researching
    case idle      // Agent is waiting
}

struct SmartHandoffWidget: View {
    @EnvironmentObject var appContext: AppContext
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text(appContext.currentActivity == .idle ? "Status" : "Action Required")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // Dynamic Content Swapper
            ZStack {
                switch appContext.currentActivity {
                case .coding(let filename):
                    CodeHandoffView(filename: filename)
                case .browsing(let url):
                    WebHandoffView(url: url)
                case .idle:
                    IdleStateView()
                }
            }
            .transition(.opacity)
            .animation(.easeInOut, value: appContext.currentActivity.stateId)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.3))
        .background(.ultraThinMaterial)
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(stateColor.opacity(0.3), lineWidth: 1))
    }
    
    var stateColor: Color {
        switch appContext.currentActivity {
        case .coding: return .blue
        case .browsing: return .orange
        case .idle: return .gray
        }
    }
}

// Helper for animation identity
extension AgentActivityType {
    var stateId: String {
        switch self {
        case .idle: return "idle"
        case .coding: return "coding"
        case .browsing: return "browsing"
        }
    }
}

// --- Subviews for Handoff Widget ---

struct CodeHandoffView: View {
    let filename: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("main.py")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .fontDesign(.monospaced)
                    Text("Ready to review")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                Spacer()
            }
            Spacer()
            
            Button(action: { }) {
                HStack {
                    Text("Open Project")
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }
}

struct WebHandoffView: View {
    let url: String
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "safari.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Research")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("Documentation")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            Spacer()
            
            Button(action: { }) {
                HStack {
                    Text("Open Safari")
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: "safari")
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Color.orange.opacity(0.8))
                .foregroundStyle(.black)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }
}

struct IdleStateView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.2))
            Text("Listening...")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}