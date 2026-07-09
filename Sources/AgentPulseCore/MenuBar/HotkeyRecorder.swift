import AppKit
import Carbon
import SwiftUI

/// Records a global-hotkey shortcut for the pinned overlay. Click to arm, then
/// press a modifier + key combo. A bare key (no modifier) is ignored so it
/// can't hijack normal typing.
struct HotkeyRecorder: View {
    @ObservedObject var settings: HotkeySettings
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Press keys…" : settings.shortcut.displayString)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 90)
            }

            Button("Reset") {
                stopRecording()
                settings.reset()
            }
            .disabled(settings.isDefault)
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }

        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let candidate = HotkeyShortcut(keyCode: Int(event.keyCode), modifierFlags: Int(flags.rawValue))

            // Esc cancels; a combo needs at least one modifier.
            if event.keyCode == kVK_Escape {
                stopRecording()
            } else if candidate.hasModifier {
                settings.setShortcut(candidate)
                stopRecording()
            }
            return nil // consume the event while recording
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
