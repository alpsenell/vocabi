import StoreKit
import SwiftUI
import VocabCore

/// Settings → "Vocabi Pro": status, upgrade / manage, custom topics, AI pack library and refresh.
struct ProSettingsSection: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var sync: PackSyncService
    @State private var showPaywall = false
    @State private var showManage = false

    var body: some View {
        Section {
            statusRow
            if store.hasRealSubscription {
                Button { showManage = true } label: {
                    Label("Manage subscription", systemImage: "creditcard")
                }
            } else {
                Button { showPaywall = true } label: {
                    Label("Upgrade to Pro", systemImage: "sparkles")
                }
            }
            NavigationLink {
                CustomTopicsView()
            } label: {
                LabeledContent {
                    if store.isPro {
                        Text(verbatim: "\(model.settings.customTopics.count)/\(UserSettings.maxCustomTopics)")
                    } else {
                        Image(systemName: "lock.fill")
                    }
                } label: {
                    Label("Custom topics", systemImage: "text.badge.plus")
                }
            }
            libraryRow
            if store.isPro {
                Button {
                    sync.sync(settings: model.settings, isEntitled: store.isPro)
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }
                .disabled(sync.isSyncing)
            }
            if !store.hasRealSubscription {
                Button {
                    Task { await store.restore() }
                } label: {
                    Label("Restore purchases", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(store.isRestoring)
            }
        } header: {
            Text("Vocabi Pro")
        } footer: {
            if case .failed(let message) = sync.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if !store.isPro {
                Text("Pro adds AI word packs for your levels and topics, plus up to 5 custom topics.")
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .alert("Vocabi Pro", isPresented: Binding(get: { store.errorMessage != nil && !showPaywall },
                                                  set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: store.isPro ? "crown.fill" : "crown")
                .font(.title3)
                .foregroundStyle(store.isPro ? Color.yellow : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.isPro ? "Pro is active" : "Free plan").font(.headline)
                if let detail = statusDetail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var statusDetail: String? {
        guard store.hasRealSubscription else {
            return store.isPro ? String(localized: "Developer access") : nil
        }
        let plan = store.entitlement.product == .weekly ? String(localized: "Weekly") : String(localized: "Monthly")
        if let expires = store.entitlement.expiresAt {
            return String(localized: "\(plan) · renews \(expires.formatted(date: .abbreviated, time: .omitted))")
        }
        return plan
    }

    private var libraryRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(Color.purple)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI word packs")
                Text("\(sync.summary.packCount) packs, \(sync.summary.wordCount) words")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Group {
                    switch sync.state {
                    case .syncing(let done, let total):
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Updating… \(done)/\(total)")
                        }
                    default:
                        if let last = sync.lastSync {
                            Text("Last updated \(last.formatted(.relative(presentation: .named)))")
                        } else {
                            Text("Not updated yet")
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Small "AI" sparkle capsule shown on AI-generated words.
struct AIBadge: View {
    /// Use on colored backgrounds (the Home hero card).
    var onAccent = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
            Text(verbatim: "AI")
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(onAccent ? Color.white : Color.purple)
        .background(onAccent ? Color.white.opacity(0.22) : Color.purple.opacity(0.14), in: Capsule())
        .accessibilityLabel(Text("AI-generated word"))
    }
}
