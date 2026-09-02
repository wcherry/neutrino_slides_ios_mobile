import SwiftUI
import UIKit
import NeutrinoAuth
import NeutrinoCrypto
import NeutrinoUI

// MARK: - SettingsView

/// Settings: appearance, the editor's own preferences and auto-save, presenting, plus the
/// encryption-key, app-lock and registered-device controls Epics 2 and 3 imply.
struct SettingsView: View {

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var biometricService: BiometricAuthService

    @State private var hasKeys = KeyImportService.hasStoredKeys()
    @State private var showKeyImport = false
    @State private var showVaultUnlock = false
    @State private var showRemoveKeysConfirmation = false
    @State private var showSignOutConfirmation = false

    var body: some View {
        List {
            appearanceSection
            editorSection
            presentingSection
            encryptionSection
            securitySection
            accountSection
        }
        .navigationTitle("Settings")
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
        }
    }

    // MARK: - Editor

    private var editorSection: some View {
        Section {
            Toggle("Slide Thumbnails", isOn: $settings.showThumbnails)
            Toggle("Speaker Notes", isOn: $settings.showNotes)

            if FeatureFlags.deckEditing {
                Picker("Snap to Grid", selection: $settings.snapStep) {
                    ForEach(AppSettings.snapStepOptions, id: \.self) { step in
                        Text(AppSettings.snapLabel(for: step)).tag(step)
                    }
                }
                Toggle("Alignment Guides", isOn: $settings.showSnapGuides)
            }

            Picker("Auto-Save", selection: $settings.autoSaveInterval) {
                ForEach(AppSettings.autoSaveIntervalOptions, id: \.self) { interval in
                    Text(AppSettings.autoSaveLabel(for: interval)).tag(interval)
                }
            }
        } header: {
            Text("Editor")
        } footer: {
            Text("Snapping is measured across the slide, not in points, so a deck laid out here "
                 + "lines up with the same deck on a computer.")
        }
    }

    // MARK: - Presenting

    private var presentingSection: some View {
        Section {
            Picker("Advance Slides", selection: $settings.advanceSeconds) {
                ForEach(AppSettings.advanceSecondsOptions, id: \.self) { seconds in
                    Text(AppSettings.advanceLabel(for: seconds)).tag(seconds)
                }
            }
            Toggle("Keep Screen Awake", isOn: $settings.keepScreenAwake)
        } header: {
            Text("Presenting")
        } footer: {
            Text("The screen is only kept awake while a presentation is playing. Tap the right half "
                 + "of the screen to advance, the left half to go back, and hold either to show the "
                 + "controls.")
        }
    }

    // MARK: - Encryption

    private var encryptionSection: some View {
        Section {
            if hasKeys {
                Label("Encryption key imported", systemImage: "key.fill")
                    .foregroundStyle(.primary)

                Button("Remove Keys", role: .destructive) {
                    showRemoveKeysConfirmation = true
                }
                .alert("Remove Encryption Keys?", isPresented: $showRemoveKeysConfirmation) {
                    Button("Remove", role: .destructive) {
                        Task {
                            // Removing keys makes every presentation unreadable on this device, so
                            // it sits behind the same gate as unlocking the app.
                            guard await biometricService.authenticateForKeyAccess() else { return }
                            KeyImportService.removeKeys()
                            hasKeys = false
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your presentations stay encrypted on the server. You\u{2019}ll need to import your key again to read them on this device.")
                }
            } else {
                // Preferred path: the key is already on the server, wrapped. Unlocking with the
                // encryption password fetches it here, so no file has to be moved between devices.
                Button {
                    showVaultUnlock = true
                } label: {
                    Label("Unlock with Password", systemImage: "lock.open")
                }
                .sheet(isPresented: $showVaultUnlock) {
                    hasKeys = KeyImportService.hasStoredKeys()
                } content: {
                    VaultUnlockView(isPresented: $showVaultUnlock) {
                        hasKeys = KeyImportService.hasStoredKeys()
                    }
                }

                // Manual import stays for accounts created before the vault, and for moving a key
                // between accounts.
                Button {
                    showKeyImport = true
                } label: {
                    Label("Import Key File", systemImage: "key")
                }
                .sheet(isPresented: $showKeyImport) {
                    hasKeys = KeyImportService.hasStoredKeys()
                } content: {
                    KeyImportView(isPresented: $showKeyImport)
                }
            }
        } header: {
            Text("Encryption")
        } footer: {
            Text("Your key is stored in the Keychain on this device only, and is never sent to the server.")
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        Section("Security") {
            NavigationLink {
                BiometricSettingsView(biometricService: biometricService)
            } label: {
                Label("App Lock", systemImage: "lock")
            }

            NavigationLink {
                DevicesView()
            } label: {
                Label("Registered Devices", systemImage: "iphone")
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            Button("Sign Out", role: .destructive) {
                showSignOutConfirmation = true
            }
            .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    authService.logout()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your encryption key stays on this device.")
            }

            Button("Reset Settings to Defaults") {
                settings.resetToDefaults()
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Neutrino Slides \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
        }
    }
}

// MARK: - BiometricSettingsView

/// Epic 3 — "Face ID / Touch ID vault unlock", and Epic 29's app lock.
struct BiometricSettingsView: View {

    @ObservedObject var biometricService: BiometricAuthService

    @State private var gracePeriod: TimeInterval = BiometricAuthService.defaultGracePeriod
    @State private var showUnavailableAlert = false

    var body: some View {
        Form {
            Section {
                Toggle("Require \(biometricService.biometryName)", isOn: $biometricService.isEnabled)
                    .disabled(!availability.canEnable && !biometricService.isEnabled)
                    .onChange(of: biometricService.isEnabled) { newValue in
                        // The service reverts the toggle itself when biometrics are unusable;
                        // surface the reason rather than letting it silently flip back.
                        if !newValue, biometricService.lastError != nil, !availability.canEnable {
                            showUnavailableAlert = true
                        }
                    }
            } footer: {
                Text(footerText)
            }

            if biometricService.isEnabled {
                Section {
                    Picker("Lock After", selection: $gracePeriod) {
                        ForEach(BiometricAuthService.gracePeriodOptions, id: \.self) { seconds in
                            Text(Self.label(for: seconds)).tag(seconds)
                        }
                    }
                    .onChange(of: gracePeriod) { newValue in
                        biometricService.gracePeriod = newValue
                    }
                } header: {
                    Text("Grace Period")
                } footer: {
                    Text("How long the app may stay in the background before it locks again. Your presentations are hidden from the app switcher immediately, regardless of this setting.")
                }
            }

            if !availability.canEnable {
                Section {
                    Label(availability.explanation, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        .navigationTitle("App Lock")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { gracePeriod = biometricService.gracePeriod }
        .alert("Cannot Enable", isPresented: $showUnavailableAlert) {
            Button("OK") {}
        } message: {
            Text(availability.explanation)
        }
    }

    private var availability: BiometricAvailability { biometricService.availability() }

    private var footerText: String {
        biometricService.isEnabled
            ? "Neutrino Slides asks for \(biometricService.biometryName) — or your device passcode — before showing your presentations, and before your encryption key can be removed."
            : "When on, Neutrino Slides asks for \(biometricService.biometryName) before showing your presentations. Your device passcode always works as a fallback, so a locked-out sensor never strands you."
    }

    private static func label(for seconds: TimeInterval) -> String {
        switch seconds {
        case 0:   return "Immediately"
        case 60:  return "After 1 minute"
        case 300: return "After 5 minutes"
        case 900: return "After 15 minutes"
        default:  return "After \(Int(seconds))s"
        }
    }
}

// MARK: - DevicesView

/// Epic 2 — "Device registration". Lists the devices registered against this account and revokes
/// them.
struct DevicesView: View {

    @EnvironmentObject private var deviceService: DeviceSessionService

    @State private var revokeTarget: DeviceSession?

    var body: some View {
        List {
            Section {
                if deviceService.sessions.isEmpty && !deviceService.isLoading {
                    Text("No registered devices found.")
                        .foregroundStyle(.secondary)
                }

                ForEach(deviceService.sessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(session.displayName).lineLimit(1)
                            if session.isCurrentDevice {
                                Text("This device")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(session.lastUsedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            revokeTarget = session
                        } label: {
                            Label("Revoke", systemImage: "xmark.circle")
                        }
                    }
                }
            } header: {
                Text("Devices")
            } footer: {
                Text("This device registered as \u{201C}\(DeviceIdentity.deviceName)\u{201D} when you signed in. Revoking signs that device out.")
            }
        }
        .navigationTitle("Registered Devices")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await deviceService.load() }
        .task { await deviceService.load() }
        .overlay {
            if deviceService.isLoading && deviceService.sessions.isEmpty { ProgressView() }
        }
        .alert("Revoke this device?", isPresented: Binding(
            get: { revokeTarget != nil },
            set: { if !$0 { revokeTarget = nil } }
        )) {
            Button("Revoke", role: .destructive) {
                if let target = revokeTarget {
                    Task { await deviceService.revoke(sessionID: target.id) }
                }
                revokeTarget = nil
            }
            Button("Cancel", role: .cancel) { revokeTarget = nil }
        } message: {
            Text(revokeTarget?.isCurrentDevice == true
                 ? "This is the device you\u{2019}re using. Revoking it signs you out here."
                 : "That device will need to sign in again.")
        }
    }
}
