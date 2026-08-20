import Foundation

/// The one thing naming needs to know about a target format: which extension
/// the file gets. Lets `OutputNaming`, `NameReserver` and `NameTemplate` serve
/// images and video without duplication.
public protocol OutputFormat: Sendable {
    var fileExtension: String { get }
}

extension TargetFormat: OutputFormat {}
extension VideoCodec: OutputFormat {}
