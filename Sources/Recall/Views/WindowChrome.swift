import AppKit
import SwiftUI

// AppKit's automatic titlebar separator extends into the sidebar's divider
// hit area. A seamless unified titlebar avoids that overhang at every width.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowObserver { WindowObserver() }

    func updateNSView(_ view: WindowObserver, context: Context) {
        view.window?.titlebarSeparatorStyle = .none
    }

    final class WindowObserver: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titlebarSeparatorStyle = .none
        }
    }
}
