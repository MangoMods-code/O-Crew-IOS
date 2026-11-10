import SwiftUI

@MainActor
struct PauseView: View {
    let title: String
    let subtitle: String
    let onResume: () -> Void
    let onSettings: () -> Void
    let onHelp: () -> Void
    let onRestart: () -> Void
    let onQuit: () -> Void
    @State private var confirmRestart = false

    var body: some View {
        OverlayPanel(title: "Paused", subtitle: "\(title) · \(subtitle)", maxWidth: 440, onClose: onResume) {
            VStack(spacing: 10) {
                Button(action: onResume) { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(BrandButtonStyle())
                HStack(spacing: 10) {
                    Button(action: onSettings) { Label("Settings", systemImage: "gearshape.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(filled: false))
                    Button(action: onHelp) { Label("How to play", systemImage: "questionmark.circle.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(filled: false))
                }
                if confirmRestart {
                    Button(action: onRestart) { Text("Tap again — start over with a fresh mess").frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(color: 0xB03A2E))
                } else {
                    Button { confirmRestart = true } label: { Label("Restart level", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(filled: false))
                }
                Button(action: onQuit) { Label("Save & quit to menu", systemImage: "door.left.hand.open").frame(maxWidth: .infinity) }
                    .buttonStyle(BrandButtonStyle(filled: false))
                Text("Your progress in this level is saved — you can pick up right where you left off.")
                    .font(.system(size: 12)).foregroundColor(Color(hex: Theme.dim))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

@MainActor
struct LevelCompleteView: View {
    let result: LevelResult
    let onNext: (() -> Void)?
    let onReplay: () -> Void
    let onMenu: () -> Void
    @State private var shownStars = 0
    @State private var shownScore = 0

    private func fmt(_ t: Double) -> String {
        let v = Int(t)
        return String(format: "%d:%02d", v / 60, v % 60)
    }

    var body: some View {
        let r = result
        OverlayPanel(title: "Store Spotless!", subtitle: "\(r.level.title) · \(r.level.stageName)", maxWidth: 680) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < r.stars ? "star.fill" : "star")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(i < r.stars ? Color(hex: 0xF4D03F) : Color.white.opacity(0.25))
                            .scaleEffect(i < shownStars || i >= r.stars ? 1 : 0.2)
                            .opacity(i < shownStars || i >= r.stars ? 1 : 0)
                            .rotationEffect(.degrees(i < shownStars || i >= r.stars ? 0 : -40))
                    }
                }
                VStack(spacing: 0) {
                    Text("\(shownScore.formatted())")
                        .font(.system(size: 34, weight: .black).monospacedDigit())
                        .foregroundColor(Color(hex: 0xFFD54A))
                    Text(r.newBestScore && r.bestScore != nil ? "NEW BEST SCORE" : "SCORE")
                        .font(.system(size: 11, weight: .heavy)).foregroundColor(Color(hex: Theme.dim))
                }
                HStack(spacing: 8) {
                    StatTile(label: "Time", value: fmt(r.time), color: r.newBest && r.bestTime != nil ? Color(hex: 0xFFD54A) : .white)
                    StatTile(label: "3★ time", value: fmt(r.par))
                    StatTile(label: "Best combo", value: "\(r.bestStreak)")
                    StatTile(label: "Mistakes", value: "\(r.mistakes)")
                }
                HStack(spacing: 14) {
                    bonus("Sorting", r.baseScore)
                    bonus("Speed bonus", r.timeBonus)
                    bonus("No mistakes", r.cleanBonus)
                }
                if r.stars < 3 {
                    Text(r.stars == 2 ? "Finish under \(fmt(r.par)) for 3 stars." : "Finish under \(fmt(r.par * 1.5)) for 2 stars, \(fmt(r.par)) for 3.")
                        .font(.system(size: 12)).foregroundColor(Color(hex: Theme.dim))
                }
                HStack(spacing: 10) {
                    Button(action: onMenu) { Label("Menu", systemImage: "house.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(filled: false))
                    Button(action: onReplay) { Label("Replay", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(filled: false))
                    if let next = onNext, let n = r.next {
                        Button(action: next) {
                            VStack(spacing: 1) {
                                Text("Next level").font(.system(size: 16, weight: .bold))
                                Text("\(n.title) · \(n.stageName)").font(.system(size: 11, weight: .semibold)).opacity(0.85).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BrandButtonStyle())
                    }
                }
                if r.next == nil {
                    Text("That was the last store. Every aisle in town is spotless!")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(Color(hex: Theme.dim))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .task { await reveal() }
    }

    private func bonus(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: Theme.dim))
            Text("+\(value.formatted())").font(.system(size: 12, weight: .heavy).monospacedDigit())
                .foregroundColor(value > 0 ? .white : Color(hex: Theme.dim))
        }
    }

    /// Stars pop in one by one, then the score counts up.
    private func reveal() async {
        for i in 0..<result.stars {
            try? await Task.sleep(nanoseconds: 320_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { shownStars = i + 1 }
            Feedback.shared.play(.star, volume: 0.7)
            Feedback.shared.haptic(.medium)
        }
        let steps = 24
        for k in 1...steps {
            try? await Task.sleep(nanoseconds: 28_000_000)
            shownScore = result.score * k / steps
        }
    }
}
