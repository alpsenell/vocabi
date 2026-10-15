import SwiftUI
import VocabCore

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 88))
                .foregroundStyle(Color.accentColor.gradient)
                .padding(28)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            Text("Welcome to Vocabi")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Learn a new word every time you look at your home screen, then test yourself in quick quizzes.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                feature("rectangle.grid.2x2.fill", "Words on your home screen")
                feature("brain.head.profile", "10-question quizzes")
                feature("trophy.fill", "Global leaderboard")
            }
            .card(padding: 20)
        }
    }

    private func feature(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text).font(.body.weight(.medium)) } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 28)
        }
    }
}

struct OnboardingLanguagesStep: View {
    @Binding var draft: UserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingStepHeader(title: "Your languages",
                                 subtitle: "Words appear in the language you learn; definitions in the language you speak.",
                                 systemImage: "globe")
            languageSection("I speak", selection: $draft.nativeLanguage)
            languageSection("I want to learn", selection: $draft.targetLanguage)
            if draft.nativeLanguage == draft.targetLanguage {
                ValidationMessage(text: "Choose two different languages.")
            }
        }
    }

    private func languageSection(_ title: LocalizedStringKey, selection: Binding<Language>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Language.allCases) { lang in
                    Button { selection.wrappedValue = lang } label: {
                        HStack {
                            Text(lang.flag).font(.title2)
                            Text(lang.nativeName).font(.body.weight(.medium)).foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selection.wrappedValue == lang ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.wrappedValue == lang ? .isSelected : [])
                }
            }
        }
    }
}

struct OnboardingDifficultyStep: View {
    @Binding var draft: UserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingStepHeader(title: "Your level", subtitle: "Pick one or more levels.", systemImage: "chart.bar.fill")
            ForEach(Difficulty.allCases) { d in
                SelectionTile(title: d.localizedName, systemImage: d.symbolName,
                              isSelected: draft.difficulties.contains(d)) { draft.difficulties.toggle(d) }
            }
            if draft.difficulties.isEmpty {
                ValidationMessage(text: "Select at least one level.")
            }
        }
    }
}

struct OnboardingCategoriesStep: View {
    @Binding var draft: UserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingStepHeader(title: "Topics", subtitle: "Choose the topics you care about.", systemImage: "square.grid.2x2.fill")
            ForEach(VocabCore.Category.allCases) { c in
                SelectionTile(title: c.localizedName, systemImage: c.symbolName,
                              isSelected: draft.categories.contains(c)) { draft.categories.toggle(c) }
            }
            if draft.categories.isEmpty {
                ValidationMessage(text: "Select at least one topic.")
            }
        }
    }
}

struct OnboardingFrequencyStep: View {
    @Binding var draft: UserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingStepHeader(title: "New word every…", subtitle: "How often should your widgets change?",
                                 systemImage: "arrow.triangle.2.circlepath")
            ForEach(RefreshFrequency.allCases) { f in
                SelectionTile(title: f.localizedName, systemImage: f.symbolName,
                              isSelected: draft.frequency == f, subtitle: f.localizedDetail) { draft.frequency = f }
            }
        }
    }
}

struct OnboardingNicknameStep: View {
    @Binding var draft: UserSettings
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingStepHeader(title: "Your nickname", subtitle: "Shown on the leaderboard. No account needed.",
                                 systemImage: "person.crop.circle.fill")
            TextField("Nickname", text: $draft.nickname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .font(.title3)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            NicknameHint(nickname: draft.nickname)
        }
        .onAppear { focused = true }
    }
}

/// Live hint for the 3–20 character rule.
struct NicknameHint: View {
    let nickname: String

    var body: some View {
        let count = Nickname.clean(nickname).count
        if count == 0 || Nickname.isValid(nickname) {
            Text("3–20 characters (\(count)/20)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ValidationMessage(text: "Nickname must be 3–20 characters.")
        }
    }
}

struct ValidationMessage: View {
    let text: LocalizedStringKey

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.red)
    }
}
