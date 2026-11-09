import AppKit
import SwiftUI

/// Native assets generated from Resources/Brand/HerdrIsland.svg.
@MainActor
enum AppBrand {
    static let mark = load("HerdrIslandMark")

    static let statusImage = makeStatusImage()

    private static func load(_ name: String) -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "pdf", subdirectory: "Brand"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing bundled brand asset: \(name).pdf")
        }
        image.accessibilityDescription = "Herdr Island"
        return image
    }

    private static func makeStatusImage() -> NSImage {
        let source = mark
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { rect in
            let height = rect.width * source.size.height / source.size.width
            let bounds = NSRect(x: 0, y: (rect.height - height) / 2, width: rect.width, height: height)
            source.draw(in: bounds)
            return true
        }
        // AppKit supplies the monochrome tint; the droplet remains transparent.
        image.isTemplate = true
        image.accessibilityDescription = "Herdr Island"
        return image
    }
}

struct BrandMarkView: View {
    var body: some View {
        Image(nsImage: AppBrand.mark)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color(red: 215 / 255, green: 239 / 255, blue: 252 / 255))
            .frame(width: 20, height: 12)
            .accessibilityHidden(true)
    }
}
