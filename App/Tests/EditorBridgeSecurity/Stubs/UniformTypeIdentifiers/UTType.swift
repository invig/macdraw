import Foundation

open class UTType: NSObject {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    public init?(filenameExtension: String) {
        identifier = filenameExtension
    }

    public var preferredMIMEType: String? { "application/octet-stream" }

    public static let png = UTType(identifier: "public.png")
    public static let svg = UTType(identifier: "public.svg-image")
}
