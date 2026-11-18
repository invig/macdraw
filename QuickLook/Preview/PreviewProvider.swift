import AppKit
import QuickLookUI
import UniformTypeIdentifiers

/// Space-bar Quick Look previews for .excalidraw files.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let json = try String(contentsOf: request.fileURL, encoding: .utf8)
        guard let png = try await SceneRenderer.shared.renderPNG(sceneJSON: json, maxPixels: 2400),
              let rep = NSBitmapImageRep(data: png) else {
            return QLPreviewReply(dataOfContentType: .plainText, contentSize: CGSize(width: 400, height: 120)) { _ in
                Data("Empty drawing".utf8)
            }
        }
        // Rendered at 2x; show at half size in points so it's crisp on Retina.
        let size = CGSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
        return QLPreviewReply(dataOfContentType: .png, contentSize: size) { _ in png }
    }
}
