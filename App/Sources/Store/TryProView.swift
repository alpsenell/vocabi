import SwiftUI
import VocabCore

/// Soft, skippable last onboarding screen used by the `.freemium` policy.
struct TryProView: View {
    var onFinish: () -> Void

    @EnvironmentObject private var store: StoreManager
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)
                    Image(systemName: "sparkles")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 132, height: 132)
                        .background(LinearGradient(colors: [.purple, .accentColor], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: Circle())
                    Text("Try Vocabi Pro")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Your free library is ready. Pro adds fresh AI word packs and words for your own topics.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 14) {
                        row("sparkles", "AI word packs for your level")
                        row("text.badge.plus", "Up to 5 custom topics")
                        row("gift.fill", "3 days free, cancel anytime")
                    }
                    .card(padding: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            VStack(spacing: 8) {
                Button("Try 3 days free") { showPaywall = true }
                    .buttonStyle(.primary)
                Button("Maybe later", action: onFinish)
                    .font(.body.weight(.medium))
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $showPaywall) {
            PaywallView(onUnlocked: onFinish)
        }
    }

    private func row(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text).font(.body.weight(.medium)) } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 28)
        }
    }
}
