import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    let store: ClipboardStore
    @ObservedObject var prefs: AppPreferences
    @Binding var sizeLimitMB: Double
    let onDismiss: () -> Void

    @State private var showClearConfirm = false
    @State private var launchAtLogin = false
    @State private var currentUsageMB: Double = 0
    @State private var showAXAlert = false

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

            // Panel position
            VStack(alignment: .leading, spacing: 6) {
                Text("Panel Position")
                    .foregroundColor(.white)
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: $prefs.panelMode) {
                    Text("Notch").tag(PanelMode.notch)
                    Text("Follow cursor").tag(PanelMode.cursorFollow)
                }
                .pickerStyle(.segmented)
                .onChange(of: prefs.panelMode) { newMode in
                    if newMode == .cursorFollow && !AXIsProcessTrusted() {
                        showAXAlert = true
                        prefs.panelMode = .notch
                    }
                }
            }
            .alert("Accessibility Access Required", isPresented: $showAXAlert) {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enable Accessibility access in System Settings > Privacy & Security > Accessibility to use cursor-follow mode.")
            }

            Divider().background(Color.gray.opacity(0.3))

            // Storage
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Storage limit: \(Int(sizeLimitMB)) MB")
                        .foregroundColor(.white)
                        .font(.system(size: 12))
                    Spacer()
                    Text("Used: \(String(format: "%.1f", currentUsageMB)) MB")
                        .foregroundColor(currentUsageMB >= sizeLimitMB ? .red : .gray)
                        .font(.system(size: 11))
                }
                Slider(value: $sizeLimitMB, in: 10...500, step: 10)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(currentUsageMB >= sizeLimitMB ? Color.red : Color.blue)
                            .frame(width: geo.size.width * min(currentUsageMB / max(sizeLimitMB, 1), 1.0), height: 4)
                    }
                }
                .frame(height: 4)
            }
            .onAppear {
                currentUsageMB = (try? Double(store.totalSizeBytes())).map { $0 / 1_000_000 } ?? 0
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .foregroundColor(.white)
                .font(.system(size: 12))
                .onChange(of: launchAtLogin) { newValue in
                    if newValue { try? SMAppService.mainApp.register() }
                    else { try? SMAppService.mainApp.unregister() }
                }

            HStack {
                Text("Hotkey: ⌘⇧V (non-configurable in v1)")
                    .foregroundColor(.gray)
                    .font(.system(size: 11))
                Spacer()
            }

            Button("Clear All History") { showClearConfirm = true }
                .foregroundColor(.red)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .confirmationDialog("Clear all clipboard history?", isPresented: $showClearConfirm) {
                    Button("Clear All", role: .destructive) { try? store.clearAll() }
                }

            Spacer()
        }
        .padding(16)
        .background(Color(white: 0.1))
    }
}
