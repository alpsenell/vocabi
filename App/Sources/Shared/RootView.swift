import SwiftUI
import VocabCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = StoreManager()
    @StateObject private var packSync = PackSyncService()
    @State private var debugPaywall = false
    @State private var debugTopics = false

    var body: some View {
        @Bindable var model = model
        Group {
            if ProGate.requiresPaywall(isPro: store.isPro, hasCompletedOnboarding: model.settings.hasCompletedOnboarding) {
                PaywallView(mode: .hard)
            } else if model.settings.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .environmentObject(store)
        .environmentObject(packSync)
        .tint(.accentColor)
        .onOpenURL { model.handle($0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
        .task {
            packSync.onPacksChanged = { [model = self.model] in model.refresh() }
            #if DEBUG
            debugPaywall = ProDebugOptions.showPaywall
            debugTopics = ProDebugOptions.showCustomTopics
            #endif
            await store.start()
            packSync.sync(settings: model.settings, isEntitled: store.isPro)
        }
        .onChange(of: model.settings) { _, settings in
            packSync.scheduleSync(settings: settings, isEntitled: store.isPro)
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { packSync.sync(settings: model.settings, isEntitled: true) }
        }
        .sheet(isPresented: $debugPaywall) {
            PaywallView().environmentObject(store)
        }
        .sheet(isPresented: $debugTopics) {
            NavigationStack { CustomTopicsView() }
                .environment(model)
                .environmentObject(store)
        }
        .sheet(item: $model.presentedWord) { link in
            NavigationStack {
                WordDetailView(entryID: link.id)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { model.presentedWord = nil }
                        }
                    }
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            QuizView()
                .tabItem { Label("Quiz", systemImage: "brain.head.profile") }
                .tag(AppTab.quiz)
            LazyTab(isSelected: model.selectedTab == .leaderboard) { LeaderboardView() }
                .tabItem { Label("Leaderboard", systemImage: "trophy.fill") }
                .tag(AppTab.leaderboard)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
    }
}

/// Defers building `content` until its tab is first selected (TabView builds every tab eagerly),
/// so e.g. CloudKit isn't touched at launch.
private struct LazyTab<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder let content: () -> Content
    @State private var activated = false

    var body: some View {
        Group {
            if activated || isSelected {
                content()
            } else {
                Color(.systemGroupedBackground)
            }
        }
        .onChange(of: isSelected, initial: true) { _, selected in
            if selected { activated = true }
        }
    }
}
