//
//  View+KeyboardDismiss.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/20/26.
//

import SwiftUI

/// Resigns first responder anywhere in the app.
///
/// Uses the responder chain rather than a `@FocusState` binding so it works
/// without every screen having to declare and thread focus state through its
/// views — the modifier can then be applied once at the root.
enum KeyboardDismisser {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// Dismisses the keyboard when the user taps outside a text field, and when they
/// drag a scroll view.
///
/// The tap is attached with `simultaneousGesture`, **not** `onTapGesture`: a
/// normal tap gesture would swallow the event and break buttons, list rows and
/// map taps underneath. A simultaneous gesture recognises alongside them, so
/// controls keep working and the keyboard still goes away.
private struct DismissKeyboardOnTap: ViewModifier {
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded { KeyboardDismisser.dismiss() }
            )
            // Environment-propagating, so every scroll view and Form below this
            // point dismisses on drag as well.
            .scrollDismissesKeyboard(.interactively)
    }
}

extension View {
    /// Tap anywhere (or scroll) to dismiss the keyboard.
    ///
    /// Applied once at the app root, so it covers every screen.
    func dismissesKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTap())
    }
}
