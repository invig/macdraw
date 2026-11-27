import Foundation

public struct UTType {
    public init?(filenameExtension: String) { self.filenameExtension = filenameExtension }
    public let filenameExtension: String
    public var preferredMIMEType: String? { nil }
}
