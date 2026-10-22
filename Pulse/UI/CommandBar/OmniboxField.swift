import AppKit
import SwiftUI

enum OmniboxCommand {
    case moveUp
    case moveDown
    case submit
    case cancel
    /// ⇥ or → while the inline completion is selected.
    case acceptCompletion
    /// ⇧⌦ removes the highlighted history suggestion.
    case deleteSuggestion
}

/// The address field. AppKit-backed because Chrome-style inline completion needs control over
/// the selection, which SwiftUI's `TextField` doesn't offer on macOS 14.
struct OmniboxField: NSViewRepresentable {
    /// What the user typed; never includes the inline completion.
    @Binding var text: String
    /// Shown instead of the typed text, e.g. while a suggestion is highlighted with the arrow keys.
    var displayOverride: String?
    /// Starts with `text`; the remainder is shown selected.
    var inlineCompletion: String?
    let placeholder: String
    let selectsAllInitially: Bool
    let onUserEdit: (_ isDeletion: Bool) -> Void
    let onCommand: (OmniboxCommand) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20)
        field.placeholderString = placeholder
        field.stringValue = text
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        let selectsAll = selectsAllInitially
        // The field joins the window after this call.
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            guard let editor = field.currentEditor() else { return }
            if selectsAll {
                editor.selectAll(nil)
            } else {
                editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        let display = displayOverride ?? inlineCompletion ?? text
        guard let editor = field.currentEditor() as? NSTextView else {
            if field.stringValue != display { field.stringValue = display }
            return
        }
        guard editor.string != display else { return }
        editor.string = display
        let typedLength = (text as NSString).length
        let displayLength = (display as NSString).length
        if displayOverride == nil, inlineCompletion != nil, displayLength > typedLength {
            editor.setSelectedRange(NSRange(location: typedLength, length: displayLength - typedLength))
        } else {
            editor.setSelectedRange(NSRange(location: displayLength, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OmniboxField
        /// Set just before AppKit applies a deletion, so the edit isn't re-completed inline:
        /// backspacing over a completion must remove it, as in Chrome.
        private var isDeleting = false

        init(parent: OmniboxField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onUserEdit(isDeleting)
            isDeleting = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                return parent.onCommand(.moveUp)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onCommand(.moveDown)
            case #selector(NSResponder.insertNewline(_:)):
                return parent.onCommand(.submit)
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onCommand(.cancel)
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.moveRight(_:)):
                let selection = textView.selectedRange()
                let isCompletionSelected = parent.inlineCompletion != nil && selection.length > 0
                    && NSMaxRange(selection) == (textView.string as NSString).length
                if isCompletionSelected, parent.onCommand(.acceptCompletion) {
                    textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
                    return true
                }
                // Tab never leaves the field.
                return selector == #selector(NSResponder.insertTab(_:))
            case #selector(NSResponder.deleteForward(_:)) where NSApp.currentEvent?.modifierFlags.contains(.shift) == true:
                return parent.onCommand(.deleteSuggestion)
            case #selector(NSResponder.deleteBackward(_:)),
                 #selector(NSResponder.deleteForward(_:)),
                 #selector(NSResponder.deleteWordBackward(_:)),
                 #selector(NSResponder.deleteToBeginningOfLine(_:)):
                isDeleting = true
                return false
            default:
                return false
            }
        }
    }
}
