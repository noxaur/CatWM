import AppKit

extension WindowManager {
    package func prepareFocusSink() {
        guard focusSink == nil else { return }
        focusSink = {
            let sink = FocusSinkWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
            sink.isOpaque = false
            sink.backgroundColor = .clear
            sink.alphaValue = 0.01
            sink.ignoresMouseEvents = true
            sink.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
            return sink
        }()
    }

    package func parkFocus() {
        guard input.pointerAndFocus else { return }
        cancelFocusRequest()
        prepareFocusSink()
        guard let sink = focusSink else { return }
        if sink.isKeyWindow, frontmostPID() == getpid() {
            focusWriter.focusSink(CGWindowID(sink.windowNumber))
            return
        }
        if let primary = NSScreen.screens.first { sink.setFrameOrigin(NSPoint(x: 0, y: primary.frame.maxY - 1)) }
        sink.orderFrontRegardless()
        sink.makeKey()
        focusWriter.focusSink(CGWindowID(sink.windowNumber))
    }

    package func parkFocus(on screen: Screen) {
        parkFocus()
        guard !screen.frame.contains(mouseLocation()) else { return }
        warpPointer(to: screen.center)
    }
}
