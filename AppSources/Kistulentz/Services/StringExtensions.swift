import Foundation

extension String {
    /// `self`, or `nil` if empty.
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension Optional where Wrapped == String {
    /// `self` when non-nil and non-empty, otherwise `fallback`. Replaces the repeated
    /// `x?.isEmpty == false ? x! : fallback` pattern (importer/exporter call sites that fall back
    /// to a default when an optional, possibly-blank string wasn't provided).
    func nonEmpty(or fallback: @autoclosure () -> String) -> String {
        guard let self, !self.isEmpty else { return fallback() }
        return self
    }
}
