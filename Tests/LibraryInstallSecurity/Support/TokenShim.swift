import Foundation

/// Present only while the app has no issuer. Tokens are unique per call and are
/// not registered with LibraryImporter, which is what makes an unsolicited link fail
/// once the app starts checking them.
enum TokenShimState {
    static var serial = 0
}

extension LibraryImporter {
    static func issueAddLibraryToken(for libraryURL: URL) -> String {
        TokenShimState.serial += 1
        return "issued-\(TokenShimState.serial)"
    }
}
