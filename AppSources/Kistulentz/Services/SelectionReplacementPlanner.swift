import Foundation

enum SelectionReplacementPlanner {
    static func replace(
        in text: String,
        range: NSRange,
        expected: String,
        with replacement: String
    ) -> String? {
        let source = text as NSString
        guard range.location != NSNotFound,
              range.length > 0,
              NSMaxRange(range) <= source.length,
              source.substring(with: range) == expected else { return nil }
        return source.replacingCharacters(in: range, with: replacement)
    }
}
