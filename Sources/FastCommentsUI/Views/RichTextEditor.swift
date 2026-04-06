#if canImport(UIKit)
import SwiftUI
import UIKit

private enum RichTextEditorLayout {
    static let horizontalInset: CGFloat = 16
    static let verticalInset: CGFloat = 10
}

// MARK: - RichTextEditorContext

/// Shared context between SwiftUI toolbar buttons and the UITextView.
@MainActor
public final class RichTextEditorContext: ObservableObject {
    weak var textView: UITextView?
    var onTextChange: ((NSAttributedString) -> Void)?
    var onPlainTextChange: ((String) -> Void)?

    // MARK: - Formatting

    func toggleBold() {
        guard let textView else { return }
        toggleTrait(.traitBold, on: textView)
    }

    func toggleItalic() {
        guard let textView else { return }
        toggleTrait(.traitItalic, on: textView)
    }

    func toggleStrikethrough() {
        guard let textView else { return }
        let range = textView.selectedRange

        textView.undoManager?.beginUndoGrouping()
        if range.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            let hasStrike = (mutable.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue

            if hasStrike {
                mutable.removeAttribute(.strikethroughStyle, range: range)
            } else {
                mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            textView.attributedText = mutable
            textView.selectedRange = range
            notifyChange()
        } else {
            var attrs = textView.typingAttributes
            let hasStrike = (attrs[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue
            if hasStrike {
                attrs.removeValue(forKey: .strikethroughStyle)
            } else {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            textView.typingAttributes = attrs
        }
        textView.undoManager?.endUndoGrouping()
    }

    func toggleCode() {
        guard let textView else { return }
        let range = textView.selectedRange

        textView.undoManager?.beginUndoGrouping()
        if range.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            let currentFont = mutable.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
            let isCode = currentFont?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false

            if isCode {
                let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
                mutable.addAttribute(.font, value: baseFont, range: range)
                mutable.removeAttribute(.backgroundColor, range: range)
            } else {
                let codeFont = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .regular)
                mutable.addAttribute(.font, value: codeFont, range: range)
                mutable.addAttribute(.backgroundColor, value: UIColor.systemGray6, range: range)
            }
            textView.attributedText = mutable
            textView.selectedRange = range
            notifyChange()
        } else {
            var attrs = textView.typingAttributes
            let currentFont = attrs[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .subheadline)
            let isCode = currentFont.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)

            if isCode {
                attrs[.font] = UIFont.preferredFont(forTextStyle: .subheadline)
                attrs.removeValue(forKey: .backgroundColor)
            } else {
                attrs[.font] = UIFont.monospacedSystemFont(ofSize: currentFont.pointSize, weight: .regular)
                attrs[.backgroundColor] = UIColor.systemGray6
            }
            textView.typingAttributes = attrs
        }
        textView.undoManager?.endUndoGrouping()
    }

    func toggleCodeBlock() {
        guard let textView else { return }
        let range = textView.selectedRange

        textView.undoManager?.beginUndoGrouping()
        if range.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            let isCodeBlock = mutable.attribute(.codeBlock, at: range.location, effectiveRange: nil) as? Bool ?? false

            if isCodeBlock {
                let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
                mutable.addAttribute(.font, value: baseFont, range: range)
                mutable.removeAttribute(.backgroundColor, range: range)
                mutable.removeAttribute(.codeBlock, range: range)
            } else {
                let codeFont = UIFont.monospacedSystemFont(
                    ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                    weight: .regular
                )
                mutable.addAttribute(.font, value: codeFont, range: range)
                mutable.addAttribute(.backgroundColor, value: UIColor.systemGray5, range: range)
                mutable.addAttribute(.codeBlock, value: true, range: range)
            }
            textView.attributedText = mutable
            textView.selectedRange = range
            notifyChange()
        } else {
            var attrs = textView.typingAttributes
            let isCodeBlock = attrs[.codeBlock] as? Bool ?? false

            if isCodeBlock {
                attrs[.font] = UIFont.preferredFont(forTextStyle: .subheadline)
                attrs.removeValue(forKey: .backgroundColor)
                attrs.removeValue(forKey: .codeBlock)
            } else {
                let currentFont = attrs[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .subheadline)
                attrs[.font] = UIFont.monospacedSystemFont(ofSize: currentFont.pointSize, weight: .regular)
                attrs[.backgroundColor] = UIColor.systemGray5
                attrs[.codeBlock] = true
            }
            textView.typingAttributes = attrs
        }
        textView.undoManager?.endUndoGrouping()
    }

    func applyLink(url: URL, label: String) {
        guard let textView else { return }
        let range = textView.selectedRange

        textView.undoManager?.beginUndoGrouping()
        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)

        if range.length > 0 {
            mutable.addAttribute(.link, value: url, range: range)
        } else {
            let linkText = NSAttributedString(string: label.isEmpty ? url.absoluteString : label, attributes: [
                .link: url,
                .font: UIFont.preferredFont(forTextStyle: .subheadline)
            ])
            mutable.insert(linkText, at: range.location)
        }
        textView.attributedText = mutable
        textView.undoManager?.endUndoGrouping()
        notifyChange()
    }

    func selectedText() -> String? {
        guard let textView else { return nil }
        let range = textView.selectedRange
        guard range.length > 0 else { return nil }
        return (textView.text as NSString).substring(with: range)
    }

    // MARK: - Private

    private func notifyChange() {
        guard let textView else { return }
        onTextChange?(textView.attributedText)
        (textView as? SelfSizingTextView)?.invalidateHeight()
    }

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits, on textView: UITextView) {
        let range = textView.selectedRange

        textView.undoManager?.beginUndoGrouping()
        if range.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            let currentFont = mutable.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
                ?? UIFont.preferredFont(forTextStyle: .subheadline)
            let hasTrait = currentFont.fontDescriptor.symbolicTraits.contains(trait)

            mutable.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                guard let font = value as? UIFont else { return }
                var newTraits = font.fontDescriptor.symbolicTraits
                if hasTrait {
                    newTraits.remove(trait)
                } else {
                    newTraits.insert(trait)
                }
                if let newDescriptor = font.fontDescriptor.withSymbolicTraits(newTraits) {
                    let newFont = UIFont(descriptor: newDescriptor, size: font.pointSize)
                    mutable.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
            textView.attributedText = mutable
            textView.selectedRange = range
            notifyChange()
        } else {
            var attrs = textView.typingAttributes
            let currentFont = attrs[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .subheadline)
            var newTraits = currentFont.fontDescriptor.symbolicTraits

            if newTraits.contains(trait) {
                newTraits.remove(trait)
            } else {
                newTraits.insert(trait)
            }
            if let newDescriptor = currentFont.fontDescriptor.withSymbolicTraits(newTraits) {
                attrs[.font] = UIFont(descriptor: newDescriptor, size: currentFont.pointSize)
            }
            textView.typingAttributes = attrs
        }
        textView.undoManager?.endUndoGrouping()
    }
}

// MARK: - Self-sizing UITextView

/// UITextView that sizes itself via intrinsicContentSize and strips pastes to plain text.
class SelfSizingTextView: UITextView {
    private let minHeight: CGFloat = 36
    private let maxHeight: CGFloat = 250

    override var intrinsicContentSize: CGSize {
        let width = frame.width > 0 ? frame.width : 250
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let clamped = min(max(size.height, minHeight), maxHeight)
        return CGSize(width: UIView.noIntrinsicMetric, height: clamped)
    }

    func invalidateHeight() {
        invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
    }

    override func paste(_ sender: Any?) {
        if let string = UIPasteboard.general.string {
            let plainText = NSAttributedString(string: string, attributes: typingAttributes)
            textStorage.insert(plainText, at: selectedRange.location)
            selectedRange = NSRange(location: selectedRange.location + string.count, length: 0)
            delegate?.textViewDidChange?(self)
        }
    }
}

// MARK: - RichTextEditor

struct RichTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var selectedRange: NSRange
    @Binding var isFocused: Bool
    var context: RichTextEditorContext
    var placeholder: String = ""
    var baseFont: UIFont = .preferredFont(forTextStyle: .subheadline)
    var textColor: UIColor = .label

    func makeUIView(context: Context) -> SelfSizingTextView {
        let textView = SelfSizingTextView()
        textView.delegate = context.coordinator
        textView.font = baseFont
        textView.textColor = textColor
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(
            top: RichTextEditorLayout.verticalInset,
            left: RichTextEditorLayout.horizontalInset,
            bottom: RichTextEditorLayout.verticalInset,
            right: RichTextEditorLayout.horizontalInset
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.typingAttributes = [
            .font: baseFont,
            .foregroundColor: textColor
        ]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let editorContext = self.context
        editorContext.textView = textView
        editorContext.onTextChange = { newText in
            context.coordinator.parent.attributedText = newText
        }

        return textView
    }

    func updateUIView(_ textView: SelfSizingTextView, context: Context) {
        context.coordinator.isUpdatingFromSwiftUI = true
        defer { context.coordinator.isUpdatingFromSwiftUI = false }

        if textView.attributedText.string != attributedText.string {
            textView.attributedText = attributedText
        }

        if isFocused && !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isFocused && textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        var isUpdatingFromSwiftUI = false

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingFromSwiftUI else { return }
            parent.attributedText = textView.attributedText
            parent.context.onPlainTextChange?(textView.text)
            (textView as? SelfSizingTextView)?.invalidateHeight()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String?) -> Bool {
            let fullRange = NSRange(location: 0, length: textView.attributedText.length)
            var mentionRange: NSRange?
            textView.attributedText.enumerateAttribute(.mentionUserId, in: fullRange) { value, attrRange, stop in
                guard value != nil else { return }
                if NSIntersectionRange(attrRange, range).length > 0 || range.location == attrRange.location + attrRange.length {
                    if text == nil || text?.isEmpty == true {
                        mentionRange = attrRange
                        stop.pointee = true
                    }
                }
            }

            if let mentionRange {
                let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
                mutable.deleteCharacters(in: mentionRange)
                textView.attributedText = mutable
                textView.selectedRange = NSRange(location: mentionRange.location, length: 0)
                parent.attributedText = textView.attributedText
                (textView as? SelfSizingTextView)?.invalidateHeight()
                return false
            }

            var typingAttrs = textView.typingAttributes
            if typingAttrs[.mentionUserId] != nil {
                typingAttrs.removeValue(forKey: .mentionUserId)
                textView.typingAttributes = typingAttrs
            }

            return true
        }
    }
}

// MARK: - Custom attribute keys

extension NSAttributedString.Key {
    static let mentionUserId = NSAttributedString.Key("com.fastcomments.mentionUserId")
    static let imageURL = NSAttributedString.Key("com.fastcomments.imageURL")
    static let codeBlock = NSAttributedString.Key("com.fastcomments.codeBlock")
}
#endif
