import AppKit

extension String {
    /// Calculate the rendered width of this string using the specified font
    func width(using font: NSFont) -> CGFloat {
        let attributes = [NSAttributedString.Key.font: font]
        return (self as NSString).size(withAttributes: attributes).width
    }
}
