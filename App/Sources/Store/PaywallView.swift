import StoreKit
import SwiftUI
import VocabCore

/// Vocabi Pro paywall. `.sheet` mode has a close button; `.hard` mode (ProGate `.hardPaywall`)
/// cannot be dismissed and disappears once Pro is active.
struct PaywallView: View {
    enum Mode { case sheet, hard }

    var mode: Mode = .sheet
    /// Called once Pro becomes active while the paywall is visible.
    var onUnlocked: (() -> Void)?

    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var selected: ProProduct = .monthly

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    features
                    plans
                    if store.loadState == .failed {
                        Label("Couldn't reach the App Store. Prices shown are in US dollars.", systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, mode == .sheet ? 28 : 20)
                .padding(.bottom, 16)
            }
            bottomBar
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            if mode == .sheet {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .accessibilityLabel(Text("Close"))
                .padding(16)
            }
        }
        .interactiveDismissDisabled(mode == .hard || store.purchasing != nil)
        .task { if store.loadState != .loaded { await store.loadProducts() } }
        .onChange(of: store.isPro) { _, isPro in
            guard isPro else { return }
            onUnlocked?()
            if mode == .sheet { dismiss() }
        }
        .alert("Vocabi Pro", isPresented: Binding(get: { store.errorMessage != nil },
                                                  set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: Pieces

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(LinearGradient(colors: [.purple, .accentColor], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .purple.opacity(0.3), radius: 16, y: 8)
            Text("Unlock Vocabi Pro")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("Fresh AI word packs for your level, plus words for the topics you care about.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            feature("sparkles", "AI word packs", "New words for every level and category, refreshed continuously.")
            feature("text.badge.plus", "Your own topics", "Add up to 5 topics like “sailing” or “job interviews”.")
            feature("infinity", "Unlimited vocabulary", "Your widgets never run out of new words.")
            feature("checkmark.seal.fill", "Everything in Free", "Widgets, quizzes and the leaderboard stay included.")
        }
        .card(padding: 16)
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var plans: some View {
        VStack(spacing: 12) {
            PlanCard(title: "Monthly", price: store.displayPrice(for: .monthly), period: .monthly,
                     badge: savingsBadge, trialDays: store.trialDays(for: .monthly),
                     isSelected: selected == .monthly) { selected = .monthly }
            PlanCard(title: "Weekly", price: store.displayPrice(for: .weekly), period: .weekly,
                     badge: nil, trialDays: store.trialDays(for: .weekly),
                     isSelected: selected == .weekly) { selected = .weekly }
        }
        .redacted(reason: store.loadState == .loading && store.products.isEmpty ? .placeholder : [])
    }

    private var savingsBadge: String? {
        let pct = store.monthlySavingsPercent
        return pct > 0 ? String(localized: "Save \(pct)%") : nil
    }

    private var trialLine: String {
        let price = store.displayPrice(for: selected)
        if let days = store.trialDays(for: selected) {
            switch selected {
            case .monthly: return String(localized: "\(days) days free, then \(price)/month. Cancel anytime.")
            case .weekly: return String(localized: "\(days) days free, then \(price)/week. Cancel anytime.")
            }
        }
        switch selected {
        case .monthly: return String(localized: "\(price)/month. Cancel anytime.")
        case .weekly: return String(localized: "\(price)/week. Cancel anytime.")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Text(trialLine)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
            Button {
                Task { await store.purchase(selected) }
            } label: {
                if store.purchasing != nil {
                    ProgressView().tint(.white)
                } else {
                    Text(store.trialDays(for: selected) != nil ? "Start free trial" : "Subscribe")
                }
            }
            .buttonStyle(.primary)
            .disabled(store.purchasing != nil || store.isRestoring)

            HStack(spacing: 16) {
                Button {
                    Task { await store.restore() }
                } label: {
                    if store.isRestoring { ProgressView() } else { Text("Restore purchases") }
                }
                .disabled(store.isRestoring || store.purchasing != nil)
                Text(verbatim: "·").foregroundStyle(.tertiary)
                Link("Terms of Use", destination: AppInfo.termsURL)
                Text(verbatim: "·").foregroundStyle(.tertiary)
                Link("Privacy policy", destination: AppInfo.privacyPolicyURL)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .tint(.secondary)

            Text("Subscriptions renew automatically until cancelled in your App Store account settings at least 24 hours before the end of the period.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

private struct PlanCard: View {
    let title: LocalizedStringKey
    let price: String
    let period: ProProduct
    let badge: String?
    let trialDays: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.green, in: Capsule())
                        }
                    }
                    if let trialDays {
                        Text("\(trialDays)-day free trial")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: price).font(.headline)
                    Text(period == .monthly ? "per month" : "per week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color(.separator).opacity(0.5), lineWidth: isSelected ? 2.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
