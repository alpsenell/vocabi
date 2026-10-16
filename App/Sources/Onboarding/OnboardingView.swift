import SwiftUI
import VocabCore

/// First-launch flow. Builds a `UserSettings` draft and saves it on the last step.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, languages, difficulty, categories, frequency, nickname
    }

    @Environment(AppModel.self) private var model
    @State private var step: Step = .welcome
    @State private var draft = UserSettings.default
    /// `.freemium`: after the nickname step, a skippable "Try Vocabi Pro" screen.
    @State private var showTryPro = false

    var body: some View {
        if showTryPro {
            TryProView { model.completeOnboarding(with: draft) }
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            steps
        }
    }

    private var steps: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                header
            }
            ScrollView {
                stepContent
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                go(to: Step(rawValue: step.rawValue - 1))
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .accessibilityLabel(Text("Back"))
            ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                .tint(.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: OnboardingWelcomeStep()
        case .languages: OnboardingLanguagesStep(draft: $draft)
        case .difficulty: OnboardingDifficultyStep(draft: $draft)
        case .categories: OnboardingCategoriesStep(draft: $draft)
        case .frequency: OnboardingFrequencyStep(draft: $draft)
        case .nickname: OnboardingNicknameStep(draft: $draft)
        }
    }

    private var footer: some View {
        Button {
            if let next = Step(rawValue: step.rawValue + 1) {
                go(to: next)
            } else if ProGate.policy == .freemium {
                withAnimation(.snappy) { showTryPro = true }
            } else {
                // `.hardPaywall`: RootView shows the paywall as soon as onboarding is complete.
                model.completeOnboarding(with: draft)
            }
        } label: {
            Text(step == .welcome ? "Get started" : (step == .nickname ? "Start learning" : "Continue"))
        }
        .buttonStyle(.primary)
        .disabled(!canContinue)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var canContinue: Bool {
        switch step {
        case .welcome, .frequency: return true
        case .languages: return draft.nativeLanguage != draft.targetLanguage
        case .difficulty: return !draft.difficulties.isEmpty
        case .categories: return !draft.categories.isEmpty
        case .nickname: return Nickname.isValid(draft.nickname)
        }
    }

    private func go(to newStep: Step?) {
        guard let newStep else { return }
        withAnimation(.snappy) { step = newStep }
    }
}

/// Title + subtitle used at the top of every onboarding step.
struct OnboardingStepHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
}
