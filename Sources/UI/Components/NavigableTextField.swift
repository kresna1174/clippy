import AppKit
import SwiftUI

enum NavDirection { case up, down, confirm }

struct NavigableTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var onNavigate: (NavDirection) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.isEditable = true
        field.backgroundColor = .clear
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        if isFocused {
            DispatchQueue.main.async {
                guard field.currentEditor() == nil else { return }
                field.window?.makeFirstResponder(field)
            }
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NavigableTextField
        weak var field: NSTextField?

        init(_ parent: NavigableTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            parent.text = f.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) { parent.isFocused = true }
        func controlTextDidEndEditing(_ obj: Notification)   { parent.isFocused = false }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveDown(_:)):    parent.onNavigate(.down);    return true
            case #selector(NSResponder.moveUp(_:)):      parent.onNavigate(.up);      return true
            case #selector(NSResponder.insertNewline(_:)): parent.onNavigate(.confirm); return true
            default: return false
            }
        }
    }
}
