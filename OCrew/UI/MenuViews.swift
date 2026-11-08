import SwiftUI

@MainActor
struct MenuBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1B1F27), Color(hex: 0x0E1014)], startPoint: .top, endPoint: .bottom)
            // Faint aisle stripes
            GeometryReader { g in
                HStack(spacing: 46) {
                    ForEach(0..<16, id: \.self) { _ in
                        Rectangle().fill(Color.white.opacity(0.025)).frame(width: 18)
                    }
                }
                .frame(width: g.size.width * 1.6, height: g.size.height * 1.6)
                .rotationEffect(.degrees(-18))
                .offset(x: -g.size.width * 0.3, y: -g.size.height * 0.3)
            }
            RadialGradient(colors: [Color(hex: Theme.brand, opacity: 0.25), .clear], center: .topLeading, startRadius: 10, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

@MainActor
struct Logo: View {
    var size: CGFloat = 64
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle().stroke(
                    LinearGradient(colors: [Color(hex: Theme.brand), Color(hex: Theme.brand2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: size * 0.2)
                    .frame(width: size * 0.82, height: size * 0.82)
                Image(systemName: "cart.fill").font(.system(size: size * 0.3, weight: .black)).foregroundColor(.white)
            }
            .frame(width: size, height: size)
            Text("-CREW")
                .font(.system(size: size * 0.86, weight: .black))
                .italic()
                .foregroundColor(.white)
        }
    }
}

@MainActor
struct MainMenuView: View {
    let onPlay: (StoreLevel) -> Void
    @ObservedObject private var progress = ProgressStore.shared
    @State private var page: Page = .home

    enum Page { case home, stores, settings, help }

    var body: some View {
        ZStack {
            MenuBackground()
            switch page {
            case .home: home
            case .stores: StoreSelectView(onPlay: onPlay, onBack: { page = .home })
            case .settings: SettingsView(inGame: false, onClose: { page = .home })
            case .help: HowToPlayView(onClose: { page = .home })
            }
        }
        .preferredColorScheme(.dark)
    }

    private var home: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                Logo(size: 78)
                Text("Run the store. Feed the line. Don't let anyone walk out.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: Theme.dim))
                    .frame(maxWidth: 360, alignment: .leading)
                let stars = progress.data.stars.values.reduce(0, +)
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").foregroundColor(Color(hex: 0xF4D03F))
                    Text("\(stars) / \(Levels.all.count * 3) stars").font(.system(size: 14, weight: .bold))
                    Text("·  \(progress.data.unlocked.count) of \(Levels.all.count) stores unlocked")
                        .font(.system(size: 14)).foregroundColor(Color(hex: Theme.dim))
                }
            }
            VStack(spacing: 10) {
                if let last = progress.data.lastPlayed, let lvl = Levels.level(last), let save = progress.save(for: last) {
                    Button { onPlay(lvl) } label: {
                        VStack(spacing: 1) {
                            Text("Continue").font(.system(size: 18, weight: .heavy))
                            Text("\(lvl.name) · Day \(save.day)").font(.system(size: 12, weight: .semibold)).opacity(0.85)
                        }
                        .frame(width: 250)
                    }
                    .buttonStyle(BrandButtonStyle())
                }
                Button { page = .stores } label: { Label("Stores", systemImage: "building.2.fill").frame(width: 250) }
                    .buttonStyle(BrandButtonStyle(filled: progress.data.lastPlayed == nil))
                Button { page = .help } label: { Label("How to play", systemImage: "questionmark.circle.fill").frame(width: 250) }
                    .buttonStyle(BrandButtonStyle(filled: false))
                Button { page = .settings } label: { Label("Settings", systemImage: "gearshape.fill").frame(width: 250) }
                    .buttonStyle(BrandButtonStyle(filled: false))
            }
        }
        .padding(30)
    }
}

@MainActor
struct StoreSelectView: View {
    let onPlay: (StoreLevel) -> Void
    let onBack: () -> Void
    @ObservedObject private var progress = ProgressStore.shared
    @State private var confirmRestart: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(BrandButtonStyle(filled: false))
                Text("Choose a store").font(.system(size: 26, weight: .heavy))
                    .padding(.leading, 8)
                Spacer()
            }
            .padding(.horizontal, 30)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Levels.all) { lvl in card(lvl) }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 16)
    }

    private func card(_ lvl: StoreLevel) -> some View {
        let unlocked = progress.isUnlocked(lvl.id)
        let save = progress.save(for: lvl.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STORE \(lvl.number)").font(.system(size: 11, weight: .heavy)).foregroundColor(Color(hex: lvl.trim == 0x1C2833 ? Theme.brand : lvl.trim))
                Spacer()
                StarsView(count: progress.stars(lvl.id), size: 14)
            }
            Text(lvl.name).font(.system(size: 21, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
            Text(lvl.blurb).font(.system(size: 13)).foregroundColor(Color(hex: Theme.dim)).lineLimit(3)
                .frame(height: 52, alignment: .top)
            VStack(alignment: .leading, spacing: 3) {
                Label("\(lvl.days) days", systemImage: "calendar")
                Label("Goal: \(formatMoney(lvl.profitGoal)) profit", systemImage: "dollarsign.circle")
                Label(String(format: "Rating: %.1f★ or better", lvl.ratingGoal), systemImage: "star.circle")
                Label("\(lvl.products.count) products", systemImage: "shippingbox")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.85))
            Spacer(minLength: 0)
            if !unlocked {
                Label("Get 1★ on the previous store", systemImage: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: Theme.dim))
                    .frame(maxWidth: .infinity, minHeight: 42)
            } else if let save = save {
                HStack(spacing: 6) {
                    Button { onPlay(lvl) } label: { Text("Day \(save.day)").frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle())
                    Button {
                        if confirmRestart == lvl.id {
                            progress.clearSave(lvl.id)
                            confirmRestart = nil
                            onPlay(lvl)
                        } else {
                            confirmRestart = lvl.id
                        }
                    } label: {
                        Image(systemName: confirmRestart == lvl.id ? "checkmark" : "arrow.counterclockwise")
                    }
                    .buttonStyle(BrandButtonStyle(color: 0xB03A2E, filled: confirmRestart == lvl.id))
                }
            } else {
                Button { onPlay(lvl) } label: { Text(progress.stars(lvl.id) > 0 ? "Play again" : "Start").frame(maxWidth: .infinity) }
                    .buttonStyle(BrandButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 270, height: 330)
        .background(
            RoundedRectangle(cornerRadius: 20).fill(Color(hex: Theme.panel))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20).stroke(Color(hex: lvl.trim).opacity(unlocked ? 0.7 : 0.15), lineWidth: 2)
        )
        .opacity(unlocked ? 1 : 0.55)
    }
}

@MainActor
struct HowToPlayView: View {
    let onClose: () -> Void

    private let sections: [(String, String, String)] = [
        ("figure.walk", "Move & look", "Left thumb moves you (floating stick — put your thumb down anywhere on that side). Drag on the other side to look around. Swap sides in Settings → Controls."),
        ("hand.tap.fill", "Interact", "Look at something and press the big hand button, or just tap it on screen. Hold the hand button while looking at a shelf to stock fast."),
        ("desktopcomputer", "Order stock", "Use the computer by the register. Boxes arrive in the yellow loading area by the door. Space is limited, so unpack as you go."),
        ("shippingbox.fill", "Stock shelves", "Carry a box to a shelf and tap to place items. Cold stuff needs a fridge, frozen stuff a freezer. Each spot holds one product. Drop puts a box down (or takes one item back off a shelf)."),
        ("tag.fill", "Set prices", "Tap a stocked shelf (with empty hands) or use the computer. Price above market and shoppers start walking away. Under market makes them happier but cuts your margin."),
        ("barcode.viewfinder", "Checkout", "Customers line up at the counter. Tap each item to scan it. Card payers: tap the card reader. Cash payers: tap the register and count out their change."),
        ("eye.fill", "Shoplifters", "Someone heading for the door with a full basket? Look at them and tap to stop them before they get out. Eagle Eye makes them glow."),
        ("bolt.fill", "Skills", "Sprint, Rush Restock, Express Scan, Crowd Calm and Eagle Eye each have a cooldown. Use them when the store gets slammed."),
        ("star.fill", "Win the store", "Hit the profit goal and the rating goal by the last day to earn stars and unlock the next store. Missing products, high prices, long waits and wrong change all hurt your rating."),
    ]

    var body: some View {
        OverlayPanel(title: "How to play", maxWidth: 780, onClose: onClose) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(sections.indices, id: \.self) { i in
                        let s = sections[i]
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: s.0)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(hex: Theme.brand))
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.1).font(.system(size: 15, weight: .heavy))
                                Text(s.2).font(.system(size: 13)).foregroundColor(Color(hex: Theme.dim))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: Theme.panel2)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
}
