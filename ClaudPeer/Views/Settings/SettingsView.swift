import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ConnectionSettingsTab()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }

            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
        }
        .frame(width: 480)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage(AppSettings.appearanceKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettings.defaultModelKey) private var defaultModel = AppSettings.defaultModel
    @AppStorage(AppSettings.defaultMaxTurnsKey) private var defaultMaxTurns = AppSettings.defaultMaxTurns
    @AppStorage(AppSettings.defaultMaxBudgetKey) private var defaultMaxBudget = AppSettings.defaultMaxBudget
    @AppStorage(AppSettings.autoConnectSidecarKey) private var autoConnectSidecar = true

    private var selectedAppearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearance) ?? .system },
            set: { appearance = $0.rawValue }
        )
    }

    private var selectedModel: Binding<ClaudeModel> {
        Binding(
            get: { ClaudeModel(rawValue: defaultModel) ?? .sonnet },
            set: { defaultModel = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Picker("Appearance", selection: selectedAppearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            Picker("Default Model", selection: selectedModel) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }

            Stepper("Default Max Turns: \(defaultMaxTurns)", value: $defaultMaxTurns, in: 1...200)

            HStack {
                Text("Default Max Budget")
                Spacer()
                TextField("$", value: $defaultMaxBudget, format: .number)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                Text(defaultMaxBudget == 0 ? "(unlimited)" : "")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Divider()

            Toggle("Auto-connect Sidecar on Launch", isOn: $autoConnectSidecar)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Connection

private struct ConnectionSettingsTab: View {
    @AppStorage(AppSettings.wsPortKey) private var wsPort = AppSettings.defaultWsPort
    @AppStorage(AppSettings.httpPortKey) private var httpPort = AppSettings.defaultHttpPort
    @AppStorage(AppSettings.bunPathOverrideKey) private var bunPathOverride = ""
    @AppStorage(AppSettings.sidecarPathKey) private var sidecarPath = ""

    var body: some View {
        Form {
            Section("Ports") {
                HStack {
                    Text("WebSocket Port")
                    Spacer()
                    TextField("9849", value: $wsPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("HTTP API Port")
                    Spacer()
                    TextField("9850", value: $httpPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                }

                Text("Changes take effect after restarting the sidecar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Paths") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bun Path Override")
                    HStack {
                        TextField("Auto-detect", text: $bunPathOverride)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseBunPath()
                        }
                    }
                    if bunPathOverride.isEmpty {
                        Text("Will search: /opt/homebrew/bin/bun, /usr/local/bin/bun, ~/.bun/bin/bun")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Path")
                    HStack {
                        TextField("Auto-detect", text: $sidecarPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseProjectPath()
                        }
                    }
                    Text("Root directory containing the sidecar/ folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func browseBunPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the Bun executable"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            bunPathOverride = url.path
        }
    }

    private func browseProjectPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the ClaudPeer project directory"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        if panel.runModal() == .OK, let url = panel.url {
            sidecarPath = url.path
        }
    }
}

// MARK: - Advanced

private struct AdvancedSettingsTab: View {
    @AppStorage(AppSettings.dataDirectoryKey) private var dataDirectory = AppSettings.defaultDataDirectory
    @AppStorage(AppSettings.logLevelKey) private var logLevel = AppSettings.defaultLogLevel
    @State private var showResetConfirmation = false

    private var selectedLogLevel: Binding<LogLevel> {
        Binding(
            get: { LogLevel(rawValue: logLevel) ?? .info },
            set: { logLevel = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Data") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data Directory")
                    HStack {
                        TextField("~/.claudpeer", text: $dataDirectory)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseDataDirectory()
                        }
                    }
                    Text("Stores logs, blackboard data, repos, and sandboxes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Logging") {
                Picker("Log Level", selection: selectedLogLevel) {
                    ForEach(LogLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
            }

            Section {
                HStack {
                    Button("Open Data Directory in Finder") {
                        openDataDirectory()
                    }

                    Spacer()

                    Button("Reset All Settings", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .confirmationDialog(
                        "Reset all settings to defaults?",
                        isPresented: $showResetConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Reset", role: .destructive) {
                            AppSettings.resetAll()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will revert all preferences to their default values. The sidecar will need to be restarted.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func browseDataDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the data directory"
        let expandedPath = NSString(string: dataDirectory).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: expandedPath)
        if panel.runModal() == .OK, let url = panel.url {
            dataDirectory = url.path
        }
    }

    private func openDataDirectory() {
        let expandedPath = NSString(string: dataDirectory).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: expandedPath))
    }
}

#Preview {
    SettingsView()
}
