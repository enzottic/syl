//
//  EmojiKeyboardField.swift
//  FinanceTracker
//

import SwiftUI

/// A `UITextField` that opens the system emoji keyboard instead of the standard one.
///
/// iOS exposes no API for presenting the emoji keyboard directly. The only route is
/// overriding `textInputMode` with the active input mode whose `primaryLanguage` is
/// `"emoji"`. If the user removed the emoji keyboard in Settings there is no such mode,
/// the override returns nil, and the normal keyboard appears — non-emoji input is then
/// rejected by the delegate below.
final class EmojiUITextField: UITextField {
    /// A private context identifier stops UIKit from restoring whichever keyboard was
    /// last used elsewhere in the app, which would defeat the `textInputMode` override.
    override var textInputContextIdentifier: String? { "sage.emoji-field" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
    }
}

/// An invisible one-point field that raises the emoji keyboard and reports the single
/// emoji the user taps. Place it behind whatever the user actually taps and drive it
/// with `isFocused`.
struct EmojiKeyboardField: UIViewRepresentable {
    @Binding var emoji: String
    @Binding var isFocused: Bool

    func makeUIView(context: Context) -> EmojiUITextField {
        let field = EmojiUITextField()
        field.delegate = context.coordinator
        // The field is only a keyboard host — nothing it contains should be visible.
        field.tintColor = .clear
        field.textColor = .clear
        field.backgroundColor = .clear
        field.autocorrectionType = .no
        field.text = emoji
        return field
    }

    func updateUIView(_ field: EmojiUITextField, context: Context) {
        context.coordinator.parent = self
        if isFocused, !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiKeyboardField

        init(parent: EmojiKeyboardField) {
            self.parent = parent
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            // Backspace: the field always holds exactly one emoji, so there's nothing to delete.
            guard let candidate = string.last, candidate.isEmoji else { return false }
            textField.text = String(candidate)
            parent.emoji = String(candidate)
            parent.isFocused = false
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }
    }
}

extension Character {
    /// True for pictographic characters, including multi-scalar sequences (flags, skin tones,
    /// ZWJ families). The scalar-value floor filters out ASCII digits and `#`/`*`, which carry
    /// `isEmoji` only because they can form keycap sequences.
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}
