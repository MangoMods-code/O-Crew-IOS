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
                Image(systemName: "basket.fill").font(.system(size: size * 0.3, weight: .black)).foregroundColor(.white)
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
    let onPlay: (OrgLevel) -> Void
    @ObservedObject private var progress = ProgressStore.shared
    @State private var page: Page = MainMenuView.initialPage

    enum Page { case home, stores, settings, help, locker }

    private static var initialPage: Page {
        switch DebugShot.screen {
        case "levels": return .stores
        case "settings": return .settings
        case "help": return .help
        case "locker": return .locker
        default: return .home
        }
    }

    var body: some View {
        ZStack {
            StoreBackdrop().ignoresSafeArea()
            // Darken the aisle so the menu reads clearly on top of it.
            LinearGradient(colors: [Color.black.opacity(page == .home ? 0.78 : 0.86), Color.black.opacity(page == .home ? 0.5 : 0.8)],
                           startPoint: .leading, endPoint: .trailing)
                .ignoresSafeArea()
            RadialGradient(colors: [Color(hex: Theme.brand, opacity: 0.22), .clear], center: .topLeading, startRadius: 10, endRadius: 480)
                .ignoresSafeArea()
            switch page {
            case .home: home
            case .stores: StoreSelectView(onPlay: onPlay, onBack: { go(.home) })
            case .settings: SettingsView(inGame: false, onClose: { go(.home) })
            case .help: HowToPlayView(onClose: { go(.home) })
            case .locker: LockerView(onBack: { go(.home) })
            }
        }
        .preferredColorScheme(.dark)
    }

    private func go(_ p: Page) {
        Feedback.shared.play(.click, volume: 0.6)
        withAnimation(.easeOut(duration: 0.18)) { page = p }
    }

    /// The level to offer under "Continue": a saved one, or the next unplayed.
    private var continueLevel: (OrgLevel, Bool)? {
        if let last = progress.data.lastPlayed, let l = Levels.level(last), progress.save(for: last) != nil { return (l, true) }
        let idx = min(progress.data.unlocked, Levels.all.count) - 1
        guard idx >= 0 else { return nil }
        if let firstNew = Levels.all.prefix(idx + 1).first(where: { progress.stars($0.id) == 0 }) { return (firstNew, false) }
        return nil
    }

    private var home: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                Logo(size: 78)
                Text("The store's a wreck. Put every item back where it belongs, as fast as you can.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.78))
                    .frame(maxWidth: 360, alignment: .leading)
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").foregroundColor(Color(hex: 0xF4D03F))
                    Text("\(progress.totalStars) / \(Levels.all.count * 3) stars").font(.system(size: 14, weight: .bold))
                    Text("·  \(min(progress.data.unlocked, Levels.all.count)) of \(Levels.all.count) levels unlocked")
                        .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.7))
                }
            }
            VStack(spacing: 10) {
                if let c = continueLevel {
                    Button { onPlay(c.0) } label: {
                        VStack(spacing: 1) {
                            Text(c.1 ? "Continue" : "Play").font(.system(size: 18, weight: .heavy))
                            Text("\(c.0.title) · \(c.0.stageName)").font(.system(size: 12, weight: .semibold)).opacity(0.85)
                        }
                        .frame(width: 250)
                    }
                    .buttonStyle(BrandButtonStyle())
                }
                Button { go(.stores) } label: { Label("Levels", systemImage: "square.grid.3x3.fill").frame(width: 250) }
                    .buttonStyle(BrandButtonStyle(filled: continueLevel == nil))
                Button { go(.locker) } label: { Label("Locker & stats", systemImage: "tshirt.fill").frame(width: 250) }
                    .buttonStyle(BrandButtonStyle(filled: false))
                HStack(spacing: 10) {
                    Button { go(.help) } label: { Label("Help", systemImage: "questionmark.circle.fill").frame(width: 106) }
                        .buttonStyle(BrandButtonStyle(filled: false))
                    Button { go(.settings) } label: { Label("Settings", systemImage: "gearshape.fill").frame(width: 106) }
                        .buttonStyle(BrandButtonStyle(filled: false))
                }
            }
        }
        .padding(30)
    }
}

/// Glove and basket colors (unlocked with stars) plus lifetime stats.
@MainActor
struct LockerView: View {
    let onBack: () -> Void
    @ObservedObject private var progress = ProgressStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(BrandButtonStyle(filled: false))
                Text("Locker").font(.system(size: 26, weight: .heavy)).padding(.leading, 8)
                Spacer()
                Image(systemName: "star.fill").foregroundColor(Color(hex: 0xF4D03F))
                Text("\(progress.totalStars) stars").font(.system(size: 16, weight: .heavy))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    row("Gloves", items: Cosmetics.gloves, selected: progress.data.glove) { progress.setLook(glove: $0) }
                    row("Basket", items: Cosmetics.baskets, selected: progress.data.basket) { progress.setLook(basket: $0) }
                    Text("LIFETIME").font(.system(size: 11, weight: .heavy)).foregroundColor(Color(hex: Theme.brand))
                    HStack(spacing: 8) {
                        StatTile(label: "Items sorted", value: progress.data.itemsSorted.formatted())
                        StatTile(label: "Levels finished", value: "\(progress.data.levelsFinished)")
                        StatTile(label: "Best combo", value: "\(progress.data.bestCombo)")
                        StatTile(label: "Time on shift", value: timeText(progress.data.secondsPlayed))
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 16)
    }

    private func timeText(_ s: Double) -> String {
        let m = Int(s) / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    private func row(_ title: String, items: [Cosmetic], selected: Int, pick: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 11, weight: .heavy)).foregroundColor(Color(hex: Theme.brand))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { c in
                        let unlocked = progress.totalStars >= c.stars
                        Button {
                            guard unlocked else { return }
                            Feedback.shared.play(.click, volume: 0.6)
                            pick(c.id)
                        } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14).fill(Color(hex: c.color)).frame(width: 78, height: 54)
                                    if !unlocked {
                                        RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.55)).frame(width: 78, height: 54)
                                        Image(systemName: "lock.fill").foregroundColor(.white)
                                    } else if selected == c.id {
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 22, weight: .bold))
                                            .foregroundColor(.white).shadow(radius: 3)
                                    }
                                }
                                Text(c.name).font(.system(size: 11, weight: .bold)).lineLimit(1)
                                Text(unlocked ? (selected == c.id ? "Wearing" : "Unlocked") : "\(c.stars)★")
                                    .font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: Theme.dim))
                            }
                            .frame(width: 90)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: Theme.panel).opacity(0.9)))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected == c.id ? Color(hex: Theme.brand) : Color.white.opacity(0.08), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

@MainActor
struct StoreSelectView: View {
    let onPlay: (OrgLevel) -> Void
    let onBack: () -> Void
    @ObservedObject private var progress = ProgressStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(BrandButtonStyle(filled: false))
                Text("Choose a level").font(.system(size: 26, weight: .heavy))
                    .padding(.leading, 8)
                Spacer()
            }
            .padding(.horizontal, 30)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Levels.themes.indices, id: \.self) { i in card(Levels.themes[i]) }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 16)
    }

    private func card(_ theme: StoreTheme) -> some View {
        let stages = Levels.all.filter { $0.theme.id == theme.id }
        let anyUnlocked = stages.contains { progress.isUnlocked($0) }
        return VStack(alignment: .leading, spacing: 8) {
            Text(theme.name).font(.system(size: 21, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
            Text(theme.blurb).font(.system(size: 13)).foregroundColor(Color(hex: Theme.dim)).lineLimit(3)
                .frame(height: 52, alignment: .top)
            ForEach(stages) { lvl in stageRow(lvl) }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 280, height: 330)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: Theme.panel)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: theme.trim).opacity(anyUnlocked ? 0.7 : 0.15), lineWidth: 2))
        .opacity(anyUnlocked ? 1 : 0.55)
    }

    private func stageRow(_ lvl: OrgLevel) -> some View {
        let unlocked = progress.isUnlocked(lvl)
        let saved = progress.save(for: lvl.id) != nil
        return Button { if unlocked { onPlay(lvl) } } label: {
            HStack(spacing: 10) {
                Text("\(lvl.number)")
                    .font(.system(size: 15, weight: .black).monospacedDigit())
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(hex: unlocked ? lvl.theme.trim : 0x333333)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(lvl.stageName).font(.system(size: 14, weight: .bold))
                    Text(subtitle(lvl, unlocked: unlocked, saved: saved))
                        .font(.system(size: 11)).foregroundColor(Color(hex: Theme.dim)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if unlocked {
                    StarsView(count: progress.stars(lvl.id), size: 11)
                } else {
                    Image(systemName: "lock.fill").foregroundColor(Color(hex: Theme.dim))
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: Theme.panel2)))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    private func subtitle(_ lvl: OrgLevel, unlocked: Bool, saved: Bool) -> String {
        if !unlocked { return "Finish the previous level" }
        if saved { return "In progress — tap to continue" }
        if let t = progress.bestTime(lvl.id) {
            let v = Int(t)
            let time = String(format: "Best %d:%02d", v / 60, v % 60)
            if let sc = progress.bestScore(lvl.id) { return "\(time) · \(sc.formatted()) pts" }
            return time
        }
        return lvl.twists.isEmpty ? "\(lvl.products.count) kinds of products" : lvl.twists.joined(separator: " · ")
    }
}

@MainActor
struct HowToPlayView: View {
    let onClose: () -> Void

    private let sections: [(String, String, String)] = [
        ("figure.walk", "Move & look", "Left thumb moves you (floating stick: put your thumb down anywhere on that side). Drag on the other side to look. Swap sides in Settings → Controls."),
        ("basket.fill", "Grab the mess", "Look at an item on the floor and tap it (or press the hand button) to drop it in your basket. Hold the hand button to keep grabbing. Your basket has limited space."),
        ("signpost.right.fill", "Read the signs", "Hanging signs and the color-coded strip on every shelf edge name the section. Work out where each item belongs; there are no outlines to help you."),
        ("square.grid.3x3.fill", "Stock it right", "Look at a shelf spot and tap to place. Each spot holds one kind of product and identical items go together. Cold things go in fridges, frozen things in freezers."),
        ("flame.fill", "Combos & score", "Place items back to back to build a combo: every 4 in a row raises your multiplier, up to x5. Filling a spot, finishing a section and a fast, mistake-free level all pay bonuses."),
        ("checkmark.seal.fill", "Fill every shelf", "The bar on each hanging sign shows how full that unit is, and it turns green when done. The level ends when every shelf is fully stocked."),
        ("arrow.down.to.line", "Fix mistakes", "Drop takes one item off the shelf you're looking at, or drops your selected item on the floor. Later levels start with things on the wrong shelves."),
        ("trash.fill", "Expired stock", "Items with a red sticker and faded packaging are expired. Take them to the trash bin by the door."),
        ("wand.and.stars", "Skills", "Sprint, Magnet, Scanner, Auto-Sort and Time Freeze each have a cooldown. Scanner lights up the signs where your selected item belongs."),
        ("tshirt.fill", "Stars & locker", "Beat the 3★ time for full stars. Stars unlock new glove and basket colors in the Locker."),
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
