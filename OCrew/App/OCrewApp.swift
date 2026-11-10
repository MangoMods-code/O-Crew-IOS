import SwiftUI

@main
struct OCrewApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

@MainActor
struct RootView: View {
    enum Screen: Equatable {
        case menu
        case game(String, UUID)
    }

    @State private var screen: Screen = DebugShot.level.map { .game($0, UUID()) } ?? .menu

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch screen {
            case .menu:
                MainMenuView(onPlay: { lvl in screen = .game(lvl.id, UUID()) })
                    .transition(.opacity)
            case let .game(id, token):
                if let lvl = Levels.level(id) {
                    GameContainer(
                        level: lvl,
                        onExit: { withAnimation { screen = .menu } },
                        onRestart: { screen = .game(id, UUID()) },
                        onNext: { next in screen = .game(next.id, UUID()) })
                        .id(token)
                        .ignoresSafeArea()
                        .defersSystemGestures(on: .all)
                        .persistentSystemOverlays(.hidden)
                }
            }
        }
        .onAppear { _ = Feedback.shared }
    }
}
