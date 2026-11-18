import AppKit
import QuickLookThumbnailing

/// Finder / Spotlight thumbnails for .excalidraw files.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let url = request.fileURL
        let maxSize = request.maximumSize
        let maxPixels = Int(max(maxSize.width, maxSize.height) * request.scale)

        Task { @MainActor in
            do {
                let json = try String(contentsOf: url, encoding: .utf8)
                guard let png = try await SceneRenderer.shared.renderPNG(sceneJSON: json, maxPixels: maxPixels),
                      let source = CGImageSourceCreateWithData(png as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    return handler(nil, nil)  // empty drawing: Finder shows the generic icon
                }
                // Fit the drawing's aspect ratio inside the requested box.
                let aspect = CGFloat(image.width) / CGFloat(image.height)
                let size = aspect >= maxSize.width / maxSize.height
                    ? CGSize(width: maxSize.width, height: maxSize.width / aspect)
                    : CGSize(width: maxSize.height * aspect, height: maxSize.height)
                let reply = QLThumbnailReply(contextSize: size) { context in
                    context.interpolationQuality = .high
                    context.draw(image, in: CGRect(origin: .zero, size: size))
                    return true
                }
                handler(reply, nil)
            } catch {
                handler(nil, error)
            }
        }
    }
}
