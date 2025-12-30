import SwiftUI
import WebKit
import Cocoa

struct WebView: NSViewRepresentable {
    let url: URL
    
    // 1. Add a closure to capture the WKWebView instance
    // This allows us to command the webview later (e.g., "Scrape Now")
    var onViewAvailable: ((WKWebView) -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // Pass the instance back up to the parent
        DispatchQueue.main.async {
            onViewAvailable?(webView)
        }
        
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            let request = URLRequest(url: url)
            nsView.load(request)
        }
    }
}
struct WebWindowView: View {
    let url: URL
    let windowID: String
    let size: CGSize

    @EnvironmentObject var coordinator: WindowCoordinator
    
    // We hold a weak reference to the underlying webview here
    @State private var webViewInstance: WKWebView?
    @State private var extractedData: String = ""

    var body: some View {
        VStack(spacing: 0) {
            
            // Top Bar
            ZStack {
                Rectangle().fill(Color.black.opacity(0.8)).frame(height: 32)
                HStack {
                    Text(url.host ?? "Browser")
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.leading, 12)
                    
                    Spacer()
                    
                    // MARK: - SCRAPE BUTTON
                    Button("Analyze Page") {
                        scrapeGoogleResults()
                        openGmailInDefaultBrowser() // temporary for testing
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    
                    Button(action: { coordinator.closeWindow(id: windowID) }) {
                        Image(systemName: "xmark").foregroundColor(.white)
                    }
                }
            }
            
            // Browser Content
            WebView(url: url, onViewAvailable: { webView in
                self.webViewInstance = webView
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
    }
    
    // MARK: - JavaScript Injection Logic
    func openGmailInDefaultBrowser() {
        // The direct link to Gmail inbox
        guard let url = URL(string: "https://mail.google.com/mail/u/0/#inbox") else { return }
        
        // NSWorkspace launches the external app
        NSWorkspace.shared.open(url)
    }

    func scrapeGoogleResults() {
        guard let webView = webViewInstance else { return }
        
        // This JS finds the first main link in Google Search results
        // Google's structure changes, but usually main links are inside class "g" or "yuRUbf"
        let jsCode = """
        (function() {
            // 1. Find the first search result link
            // Try specific Google selectors, or fall back to the first generic link
            let firstLink = document.querySelector('div.g a'); 
            
            // 2. Find all images
            let images = Array.from(document.images).map(img => img.src);
            
            return {
                "redirect_url": firstLink ? firstLink.href : window.location.href,
                "image_count": images.length,
                "images": images,
                "page_title": document.title
            };
        })();
        """
        
        // Execute JS
        webView.evaluateJavaScript(jsCode) { (result, error) in
            if let error = error {
                print("JS Error: \(error.localizedDescription)")
            } else if let dict = result as? [String: Any] {
                // SUCCESS: You have the data in Swift!
                print("--- Scraped Data ---")
                print("Redirect to: \(dict["redirect_url"] ?? "None")")
                print("Title: \(dict["page_title"] ?? "")")
                print("Image Count: \(dict["image_count"] ?? 0)")
                print("Images: \(dict["images"] ?? "None")")
                print("-------------------")

                if let images = dict["images"] as? [String] {
                    var i = 0
                    for image in images {
                        if i >= 5 { break } // Limit to first 5 images
                        print("Image URL: \(image)")
                        let id = "image_\(UUID().uuidString)"
                        let randomX = CGFloat.random(in: 100...500)
                        let randomY = CGFloat.random(in: 100...500)
                        // It could either be a URL or base64 data
                        if image.starts(with: "data:image") {
                            // It's base64 data
                            let base64Data = image.substring(from: image.index(image.startIndex, offsetBy: 23)) // Remove data:image/...;base64,
                            print("Opening image window with ID: \(base64Data)")
                            // Further processing can be done here
                            coordinator.openDynamicWindow(id: id, view: AnyView(
                                ImageViewFromBase64(base64Data: base64Data, windowID: id) // For simplicity, show first image
                                .environmentObject(coordinator)
                                .frame(width: 600, height: 400)
                                .padding()
                                .cornerRadius(12)
                                .shadow(radius: 10)
                            ), size: CGSize(width: 600, height: 400), location: CGPoint(x: randomX, y: randomY))
                        } else {
                            // It's a URL
                            let url = image
                            print("Opening image window with URL: \(url)")
                            coordinator.openDynamicWindow(id: id, view: AnyView(
                                ImageView(imageData: ImageData(url: url, alt: nil, author: nil), windowID: id) // For simplicity, show first image
                                .environmentObject(coordinator)
                                .frame(width: 600, height: 400)
                                .padding()
                                .cornerRadius(12)
                                .shadow(radius: 10)
                            ), size: CGSize(width: 600, height: 400), location: CGPoint(x: randomX, y: randomY))
                        }
                        i += 1
                    }
                }
            }
        }
    }
}

struct WebView_Previews: PreviewProvider {
    static var previews: some View {
        WebWindowView(url: URL(string: "https://www.apple.com")!, windowID: "web_apple", size: CGSize(width: 800, height: 600))
    }
}
