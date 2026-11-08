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

    private func fmt(_ t: Double) -> String {
        let v = Int(t)
        return String(format: "%d:%02d", v / 60, v % 60)
    }

    var body: some View {
        let r = result
        OverlayPanel(title: "Store Spotless!", subtitle: "\(r.level.title) · \(r.level.stageName)", maxWidth: 640) {
            VStack(spacing: 14) {
                StarsView(count: r.stars, size: 42)
                if r.newBest && r.bestTime != nil {
                    Text("New best time!").font(.system(size: 15, weight: .heavy)).foregroundColor(Color(hex: 0xF4D03F))
                }
                HStack(spacing: 8) {
                    StatTile(label: "Time", value: fmt(r.time))
                    StatTile(label: "3★ time", value: fmt(r.par))
                    StatTile(label: "Items sorted", value: "\(r.items)")
                    StatTile(label: "Wrong placements", value: "\(r.mistakes)")
                }
                if r.stars < 3 {
                    Text(r.stars == 2 ? "Finish under \(fmt(r.par)) for 3 stars." : "Finish under \(fmt(r.par * 1.5)) for 2 stars, \(fmt(r.par)) for 3.")
                        .font(.system(size: 13)).foregroundColor(Color(hex: Theme.dim))
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
                                Text("\(n.title) · \(n.stageName)").font(.system(size: 11, weight: .semibold)).opacity(0.85)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BrandButtonStyle())
                    }
                }
                if r.next == nil {
                    Text("That was the last store. Every aisle in town is spotless!")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(Color(hex: Theme.dim))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }
}
