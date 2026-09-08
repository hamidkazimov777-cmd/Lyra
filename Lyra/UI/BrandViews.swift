import SwiftUI
import AppKit

/// Official brand mark for Lyra: renders the native high-resolution cosmic constellation icon.
struct LyraLogoView: View {
    let size: CGFloat

    private var appIcon: NSImage? {
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSApp.applicationIconImage
    }

    var body: some View {
        Group {
            if let img = appIcon {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.224)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.05, green: 0.06, blue: 0.16),
                                    Color(red: 0.08, green: 0.09, blue: 0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
