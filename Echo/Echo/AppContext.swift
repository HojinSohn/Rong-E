import SwiftUI

class AppContext: ObservableObject {
    @Published var response: String = ""
    @Published var isLoading: Bool = false
    @Published var shouldAnimate: Bool = false
}