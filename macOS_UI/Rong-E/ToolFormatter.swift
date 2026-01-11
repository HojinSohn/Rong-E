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
    
    private let hudAmber = Color(red: 1.0, green: 0.8, blue: 0.0)
    private let hudCyan = Color(red: 0.0, green: 0.9, blue: 1.0)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 1. Header (Command Name)
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(hudAmber)
                
                Text("SYSTEM_CALL > \(toolName.uppercased())")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(hudAmber)
                
                Spacer()
                
                // Pulsing Status Light
                Circle()
                    .fill(hudAmber)
                    .frame(width: 6, height: 6)
                    .shadow(color: hudAmber, radius: 4)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(hudAmber.opacity(0.1))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(hudAmber.opacity(0.3)),
                alignment: .bottom
            )
            
            // 2. Arguments Body (The "Grid")
            VStack(alignment: .leading, spacing: 6) {
                let parsedArgs = ToolFormatter.parseArgs(args)
                
                if parsedArgs.isEmpty {
                    Text("No arguments provided")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.vertical, 4)
                } else {
                    ForEach(parsedArgs, id: \.key) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text(item.key)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(hudCyan.opacity(0.8))
                                .frame(width: 80, alignment: .leading)
                            
                            Text(":")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                            
                            Text(item.value)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    LinearGradient(
                        colors: [hudAmber.opacity(0.5), hudAmber.opacity(0.1)],
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
