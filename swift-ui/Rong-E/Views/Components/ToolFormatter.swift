import Foundation
import SwiftUI

// MARK: - Tool Argument Parser
class ToolFormatter {
    typealias ArgPair = (key: String, value: String)
    
    static func parseArgs(_ args: [String: AnyCodable]) -> [ArgPair] {
        var result: [ArgPair] = []
        
        for (key, value) in args {
            let stringValue = formatAnyCodable(value)
            result.append((key: key, value: stringValue))
        }
        
        return result.sorted { $0.key < $1.key } // Sort by key for consistency
    }
    
    private static func formatAnyCodable(_ value: AnyCodable) -> String {
        switch value {
        case .string(let s):
            return s
        case .int(let i):
            return String(i)
        case .double(let d):
            return String(d)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .array(let arr):
            return "[\(arr.count) items]"
        case .dict(let dict):
            return "{\(dict.count) fields}"
        }
    }
}

// MARK: - ToolConsoleView (Jarvis-style Terminal)
struct ToolConsoleView: View {
    let toolName: String
    let args: [String: AnyCodable]
    
    private let accentColor = Color.jarvisAmber
    private let keyColor = Color.jarvisCyan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 1. Header (Command Name)
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(accentColor)
                
                Text("SYSTEM_CALL > \(toolName.uppercased())")
                    .font(JarvisFont.tag)
                    .foregroundStyle(accentColor)
                
                Spacer()
                
                // Pulsing Status Light
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: accentColor, radius: 4)
            }
            .padding(.vertical, JarvisSpacing.sm)
            .padding(.horizontal, JarvisSpacing.md)
            .background(accentColor.opacity(0.1))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(accentColor.opacity(0.3)),
                alignment: .bottom
            )
            
            // 2. Arguments Body (The "Grid")
            VStack(alignment: .leading, spacing: 6) {
                let parsedArgs = ToolFormatter.parseArgs(args)
                
                if parsedArgs.isEmpty {
                    Text("No arguments provided")
                        .font(JarvisFont.captionMono)
                        .foregroundStyle(Color.jarvisTextDim)
                        .padding(.vertical, JarvisSpacing.xs)
                } else {
                    ForEach(parsedArgs, id: \.key) { item in
                        HStack(alignment: .top, spacing: JarvisSpacing.sm) {
                            Text(item.key)
                                .font(JarvisFont.monoSmall)
                                .foregroundStyle(keyColor.opacity(0.8))
                                .frame(width: 80, alignment: .leading)
                            
                            Text(":")
                                .font(JarvisFont.monoSmall)
                                .foregroundStyle(Color.jarvisTextTertiary)
                            
                            Text(item.value)
                                .font(JarvisFont.monoSmall)
                                .foregroundStyle(Color.jarvisTextPrimary.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(JarvisSpacing.md)
        }
        .background(Color.jarvisSurfaceDeep)
        .cornerRadius(JarvisRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: JarvisRadius.medium)
                .strokeBorder(
                    LinearGradient(
                        colors: [accentColor.opacity(0.5), accentColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Preview
#if DEBUG
struct ToolConsoleView_Previews: PreviewProvider {
    static var previews: some View {
        ToolConsoleView(
            toolName: "web_search",
            args: [
                "query": .string("Tony Stark"),
                "max_results": .int(5)
            ]
        )
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
#endif
