import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let store: ClipboardStore
    @Binding var sizeLimitMB: Double
    let onDismiss: () -> Void

    @State private var showClearConfirm = false
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Done", action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
            }

            Divider().background(Color.gray.opacity(0.3))

            VStack(alignment: .leading, spacing: 4) {
                Text("Storage limit: \(Int(sizeLimitMB)) MB")
                    .foregroundColor(.white)
                    .font(.system(size: 12))
                Slider(value: $sizeLimitMB, in: 100...2000, step: 100)
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .foregroundColor(.white)
                .font(.system(size: 12))
                .onChange(of: launchAtLogin) { newValue in
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }

            HStack {
                Text("Hotkey: ⌘⇧V (non-configurable in v1)")
                    .foregroundColor(.gray)
                    .font(.system(size: 11))
                Spacer()
            }

            Button("Clear All History") {
                showClearConfirm = true
            }
            .foregroundColor(.red)
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .confirmationDialog("Clear all clipboard history?", isPresented: $showClearConfirm) {
                Button("Clear All", role: .destructive) {
                    try? store.clearAll()
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color(white: 0.1))
    }
}
