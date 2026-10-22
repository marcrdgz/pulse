import AppKit
import SwiftUI

/// Moves the window when dragging empty chrome.
///
/// Used instead of `isMovableByWindowBackground`, which would also move the window
/// when dragging tabs or the sidebar's resize handle.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}
