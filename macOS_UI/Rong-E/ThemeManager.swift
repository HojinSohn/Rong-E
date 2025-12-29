import SwiftUI

struct Theme {
    let background: Color
    let accent: Color
    let secondary: Color
    let text: Color
    
    static let dark = Theme(
        background: Color.black.opacity(0.6),
        accent: Color.white,
        secondary: Color.white.opacity(0.3),
        text: Color.white
    )
    
    static let light = Theme(
        background: Color.white.opacity(0.9),
        accent: Color.black,
        secondary: Color.black.opacity(0.3),
        text: Color.black
    )
    
    static let cyberpunk = Theme(
        background: Color(red: 0.1, green: 0.1, blue: 0.2).opacity(0.9),
        accent: Color(red: 0.0, green: 1.0, blue: 0.8), // Neon Cyan
        secondary: Color(red: 1.0, green: 0.0, blue: 0.8).opacity(0.5), // Neon Pink
        text: Color(red: 0.8, green: 1.0, blue: 1.0)
    )
}

class ThemeManager: ObservableObject {
    @Published var current: Theme = .dark
    
    func switchToDark() {
        withAnimation { current = .dark }
    }
    
    func switchToLight() {
        withAnimation { current = .light }
    }
    
    func switchToCyberpunk() {
        withAnimation { current = .cyberpunk }
    }
}
