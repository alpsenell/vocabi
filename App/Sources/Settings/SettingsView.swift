import SwiftUI
import VocabCore

/// Edits every `UserSettings` field. Valid drafts persist immediately (and reload widgets);
/// invalid ones show inline errors and are not saved until fixed.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var packSync: PackSyncService
    @State private var draft = UserSettings.default
    @State private var loaded = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                ProSettingsSection()
                languagesSection
                Section {
                    Picker(selection: $draft.frequency) {
                        ForEach(RefreshFrequency.allCases) { f in
                            Label(f.localizedName, systemImage: f.symbolName).tag(f)
                        }
                    } label: {
                        Label("New word", systemImage: "arrow.triangle.2.circlepath")
                    }
                } header: {
                    Text("Widget")
                } footer: {
                    Text(draft.frequency.localizedDetail)
                }
                difficultySection
                categorySection
                nicknameSection
                aboutSection
                Section {
                    Button("Reset progress", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Clears seen words and quiz history. Your settings are kept.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Reset progress?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset progress", role: .destructive) {
                    packSync.removeAllPacks()
                    model.resetProgress()
                    packSync.sync(settings: model.settings, isEntitled: store.isPro)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All seen words and quiz scores on this device will be deleted. This can't be undone.")
            }
        }
        .onAppear {
            if !loaded { draft = model.settings; loaded = true }
        }
        .onChange(of: model.settings) { _, new in
            // Keep in sync if settings change elsewhere (e.g. reset), unless the user has unsaved invalid edits.
            if isDraftSavable, cleaned(draft) != new { draft = new }
        }
        .onChange(of: draft) { _, new in
            if isDraftSavable { model.save(cleaned(new)) }
        }
    }

    private var isDraftSavable: Bool { draft.isValid && Nickname.isValid(draft.nickname) }

    private func cleaned(_ s: UserSettings) -> UserSettings {
        var c = s
        c.nickname = Nickname.clean(s.nickname)
        return c
    }

    // MARK: Sections

    private var languagesSection: some View {
        Section {
            Picker(selection: $draft.nativeLanguage) {
                ForEach(Language.allCases) { Text($0.label).tag($0) }
            } label: {
                Label("I speak", systemImage: "person.wave.2")
            }
            Picker(selection: $draft.targetLanguage) {
                ForEach(Language.allCases) { Text($0.label).tag($0) }
            } label: {
                Label("I'm learning", systemImage: "graduationcap")
            }
        } header: {
            Text("Languages")
        } footer: {
            if draft.nativeLanguage == draft.targetLanguage {
                ValidationMessage(text: "Choose two different languages.")
            }
        }
    }

    private var difficultySection: some View {
        Section {
            ForEach(Difficulty.allCases) { d in
                checkRow(d.localizedName, symbol: d.symbolName, tint: d.tint, isOn: draft.difficulties.contains(d)) {
                    draft.difficulties.toggle(d)
                }
            }
        } header: {
            Text("Levels")
        } footer: {
            if draft.difficulties.isEmpty { ValidationMessage(text: "Select at least one level.") }
        }
    }

    private var categorySection: some View {
        Section {
            ForEach(VocabCore.Category.allCases) { c in
                checkRow(c.localizedName, symbol: c.symbolName, tint: .accentColor, isOn: draft.categories.contains(c)) {
                    draft.categories.toggle(c)
                }
            }
        } header: {
            Text("Topics")
        } footer: {
            if draft.categories.isEmpty { ValidationMessage(text: "Select at least one topic.") }
        }
    }

    private var nicknameSection: some View {
        Section {
            TextField("Nickname", text: $draft.nickname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Leaderboard nickname")
        } footer: {
            NicknameHint(nickname: draft.nickname)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Link(destination: AppInfo.privacyPolicyURL) {
                Label("Privacy policy", systemImage: "hand.raised.fill")
            }
            LabeledContent {
                Text(verbatim: AppInfo.versionString)
            } label: {
                Label("Version", systemImage: "info.circle")
            }
        }
    }

    private func checkRow(_ title: String, symbol: String, tint: Color, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Label { Text(title).foregroundStyle(.primary) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
