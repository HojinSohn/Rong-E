import SwiftUI

class AppContext: ObservableObject {
    @Published var response: String = ""
    @Published var isLoading: Bool = false
    @Published var shouldAnimate: Bool = false
    @Published var overlayWidth: CGFloat = 300
    @Published var overlayHeight: CGFloat = 160
}