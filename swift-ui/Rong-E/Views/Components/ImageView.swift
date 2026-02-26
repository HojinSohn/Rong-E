import SwiftUI

import SwiftUI

struct ImageView: View {
    @EnvironmentObject var coordinator: WindowCoordinator
    
    let imageData: ImageData
    let windowID: String
    
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var loadError: Error?
    
    // Add a hover state for UI controls visibility
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // MARK: - 1. Background (Blurred)
                // This fills the window if the aspect ratios don't match
                if let nsImage = image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 40) // Strong blur for ambience
                        .opacity(0.6)
                        .clipped() // Keep blur inside window bounds
                } else {
                    Color.black.opacity(0.8) // Dark background while loading
                }
                
                // MARK: - 2. Main Content
                VStack {
                    if let image = image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                            // Optional: Round corners slightly for a modern card look
                            .cornerRadius(4)
                            .padding(20) // Give it breathing room from the window edges
                            .transition(.opacity.animation(.easeInOut))
                    } else if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.2)
                    } else if loadError != nil {
                        errorView
                    }
                }
            }
            // MARK: - 3. UI Overlays (Close & Info)
            .overlay(alignment: .top) {
                topControlBar
                    .opacity(isHovering || isLoading ? 1.0 : 0.0) // Fade out when not hovering
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        // Detect hover to show/hide controls
        .onHover { hovering in
            self.isHovering = hovering
        }
        .onAppear {
            loadImage()
        }
    }
    
    // MARK: - Subviews
    
    var topControlBar: some View {
        HStack(alignment: .top) {
            // Text Info
            VStack(alignment: .leading, spacing: 4) {
                if let author = imageData.author {
                    Text("Photo by \(author)")
                        .font(JarvisFont.label)
                        .foregroundStyle(Color.jarvisTextPrimary)
                }
                if let alt = imageData.alt {
                    Text(alt)
                        .font(JarvisFont.captionMono)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .lineLimit(2)
                }
            }
            .shadow(radius: 2) // Shadow for text readability over light images
            
            Spacer()
            
            // Close Button
            Button(action: {
                coordinator.closeWindow(id: windowID)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.8))
                    .background(Color.black.opacity(0.2).clipShape(Circle())) // subtle backing
            }
            .buttonStyle(.plain)
            .shadow(radius: 2)
        }
        .padding(16)
        // Add a gradient at the top so white text is readable on white images
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
            .ignoresSafeArea()
        )
    }
    
    var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.yellow)
            Text("Failed to load")
                .font(.headline)
                .foregroundColor(.white)
            Button("Retry") { loadImage() }
                .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Logic
    
    private func loadImage() {
        guard let url = URL(string: imageData.url) else { return }
        
        isLoading = true
        loadError = nil
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let data = data, let nsImage = NSImage(data: data) {
                    self.image = nsImage
                    self.resizeWindowToFit(image: nsImage)
                } else {
                    loadError = error ?? NSError(domain: "Img", code: -1)
                }
            }
        }.resume()
    }
    
    /// Updates the underlying NSWindow to match the image aspect ratio
    private func resizeWindowToFit(image: NSImage) {
        // Find the window associated with this view
        // Since we are in WindowCoordinator architecture, we can ask the coordinator
        // Or, we can find it via NSApp since we have the ID
        
        if let window = NSApp.windows.first(where: { $0.title == windowID || ($0.contentViewController as? NSHostingController<AnyView>) != nil }) {
            // Note: Matching by title/ID depends on how you set up the controller in Coordinator.
            // If you passed 'windowID' as the window title in Coordinator, this works.
            
            let imgSize = image.size
            let aspectRatio = imgSize.width / imgSize.height
            
            // Set Aspect Ratio on the window so user can resize freely but ratio stays locked
            window.contentAspectRatio = imgSize
            
            // Optional: Snap window to a better size immediately
            // Logic: Keep width fixed (e.g. 600), calculate height
            let currentFrame = window.frame
            let newHeight = currentFrame.width / aspectRatio
            
            // Animate the frame change
            window.setFrame(NSRect(x: currentFrame.minX, y: currentFrame.maxY - newHeight, width: currentFrame.width, height: newHeight), display: true, animate: true)
        }
    }
}

struct ImageViewFromBase64: View {
    @EnvironmentObject var coordinator: WindowCoordinator
    
    let base64Data: String
    let windowID: String
    
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var loadError: Error?
    // Add a hover state for UI controls visibility
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // MARK: - 1. Background (Blurred)
                // This fills the window if the aspect ratios don't match
                if let nsImage = image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 40) // Strong blur for ambience
                        .opacity(0.6)
                        .clipped() // Keep blur inside window bounds
                } else {
                    Color.black.opacity(0.8) // Dark background while loading
                }
                
                // MARK: - 2. Main Content
                VStack {
                    if let image = image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                            // Optional: Round corners slightly for a modern card look
                            .cornerRadius(4)
                            .padding(20) // Give it breathing room from the window edges
                            .transition(.opacity.animation(.easeInOut))
                    } else if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.2)
                    } else if loadError != nil {
                        errorView
                    }
                }
            }
            // MARK: - 3. UI Overlays (Close & Info)
            .overlay(alignment: .top) {
                topControlBar
                    .opacity(isHovering || isLoading ? 1.0 : 0.0) // Fade out when not hovering
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        // Detect hover to show/hide controls
        .onHover { hovering in
            self.isHovering = hovering
        }
        .onAppear {
            loadImageFromBase64()
        }
    }
    
    // MARK: - Subviews
    
    var topControlBar: some View {
        HStack(alignment: .top) {
            Spacer()
            
            // Close Button
            Button(action: {
                coordinator.closeWindow(id: windowID)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .background(Color.black.opacity(0.2).clipShape(Circle()))
            }
            .buttonStyle(.plain)
            .shadow(radius: 2)
        }
        .padding(JarvisSpacing.lg)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
            .ignoresSafeArea()
        )
    }
    
    var errorView: some View {
        VStack(spacing: JarvisSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.jarvisAmber)
            Text("Failed to load")
                .font(JarvisFont.subtitle)
                .foregroundStyle(Color.jarvisTextPrimary)
            Button("Retry") { loadImageFromBase64() }
                .buttonStyle(.borderedProminent)
        }
    }
    
    
    private func loadImageFromBase64() {
        if let data = Data(base64Encoded: base64Data),
           let nsImage = NSImage(data: data) {
            self.image = nsImage
            resizeWindowToFit(image: nsImage)
        }
    }
    
    private func resizeWindowToFit(image: NSImage) {
        if let window = NSApp.windows.first(where: { $0.title == windowID || ($0.contentViewController as? NSHostingController<AnyView>) != nil }) {
            let imgSize = image.size
            window.contentAspectRatio = imgSize
            
            let currentFrame = window.frame
            let newHeight = currentFrame.width * (imgSize.height / imgSize.width)
            
            window.setFrame(NSRect(x: currentFrame.minX, y: currentFrame.maxY - newHeight, width: currentFrame.width, height: newHeight), display: true, animate: true)
        }
    }
}

// MARK: - Preview
//
//struct ImageView_Previews: PreviewProvider {
//   static var previews: some View {
//       VStack {
//           ImageView(imageData: ImageData(
//               url: "https://images.unsplash.com/photo-1580130379624-3a069adbffc5?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixid=M3w4NDk5NzV8MHwxfHNlYXJjaHwxfHxiYXJhY2slMjBvYmFtYSUyMHBvcnRyYWl0JTIwb2ZmaWNpYWwlMjBwcmVzaWRlbnRpYWwlMjBwaG90b3xlbnwwfHx8fDE3NjcwNTUxNzh8MA&ixlib=rb-4.1.0&q=80&w=1080",
//               alt: "Sample Image",
//               author: "Placeholder.com"
//           ), windowID: "preview_image")
//           .frame(width: 600, height: 400)
//       }
//   }
//}
