import SwiftUI
import VocabCore

/// Add / remove up to `UserSettings.maxCustomTopics` free-text topics for AI word packs (Pro).
struct CustomTopicsView: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var store: StoreManager
    @State private var newTopic = ""
    @State private var showPaywall = false
    @FocusState private var fieldFocused: Bool

    static let minLength = 2
    static let maxLength = 40

    private var topics: [String] { model.settings.customTopics }
    private var isFull: Bool { topics.count >= UserSettings.maxCustomTopics }

    var body: some View {
        Form {
            if !store.isPro {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Custom topics are part of Vocabi Pro", systemImage: "lock.fill")
                            .font(.headline)
                        Text("Type any topic, like “sailing” or “job interviews”, and get AI word packs made for it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Upgrade to Pro") { showPaywall = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
            }

            Section {
                ForEach(topics, id: \.self) { topic in
                    Label(topic, systemImage: "tag.fill")
                        .foregroundStyle(store.isPro ? .primary : .secondary)
                }
                .onDelete(perform: store.isPro ? remove : nil)

                if topics.isEmpty {
                    Text("No topics yet.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Your topics")
            } footer: {
                Text("\(topics.count) of \(UserSettings.maxCustomTopics). Swipe left to remove a topic.")
            }

            Section {
                HStack {
                    TextField("e.g. sailing", text: $newTopic)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($fieldFocused)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(validation != nil)
                }
                .disabled(!store.isPro || isFull)
            } header: {
                Text("Add a topic")
            } footer: {
                if let validation, !newTopic.isEmpty {
                    ValidationMessage(text: validation)
                } else if isFull {
                    Text("You've reached the limit of \(UserSettings.maxCustomTopics) topics. Remove one to add another.")
                } else {
                    Text("New words for a topic arrive in your widgets after the next update.")
                }
            }
        }
        .navigationTitle("Custom topics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if store.isPro && !topics.isEmpty { EditButton() } }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var cleanedNewTopic: String {
        newTopic.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private var validation: LocalizedStringKey? {
        let t = cleanedNewTopic
        if !store.isPro { return "Upgrade to Vocabi Pro to add topics." }
        if isFull { return "You've reached the topic limit." }
        if t.count < Self.minLength { return "Topics need at least 2 characters." }
        if t.count > Self.maxLength { return "Topics can be at most 40 characters." }
        let key = UserSettings.normalizeTopic(t)
        if topics.contains(where: { UserSettings.normalizeTopic($0) == key }) { return "You already added this topic." }
        return nil
    }

    private func add() {
        guard validation == nil else { return }
        var s = model.settings
        s.customTopics.append(cleanedNewTopic)
        model.save(s)
        newTopic = ""
    }

    private func remove(at offsets: IndexSet) {
        var s = model.settings
        s.customTopics.remove(atOffsets: offsets)
        model.save(s)
    }
}
