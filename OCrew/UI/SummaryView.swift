import SwiftUI

@MainActor
struct SummaryView: View {
    let summary: DaySummary
    let symbol: String
    let onContinue: () -> Void

    private var cb: ColorblindMode { SettingsStore.shared.display.colorblind }

    var body: some View {
        let s = summary
        let st = s.stats
        OverlayPanel(title: s.isLastDay ? (s.passed ? "Level Complete!" : "Level Failed") : "Day \(s.day) Complete",
                     subtitle: "\(s.levelName) · Day \(s.day) of \(s.totalDays)", maxWidth: 780) {
            ScrollView {
                VStack(spacing: 12) {
                    if s.isLastDay {
                        VStack(spacing: 6) {
                            StarsView(count: s.stars, size: 34)
                            Text(s.passed
                                 ? (s.nextLevelName.map { "Unlocked: \($0)" } ?? "You beat every store. Legend.")
                                 : "You needed \(formatMoney(s.profitGoal, symbol: symbol)) profit and a \(String(format: "%.1f", s.ratingGoal))★ rating. Try again!")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(hex: Theme.dim))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 4)
                    }
                    HStack(spacing: 8) {
                        StatTile(label: "Revenue", value: formatMoney(st.revenue, symbol: symbol))
                        StatTile(label: "Stock bought", value: formatMoney(st.stockSpend, symbol: symbol))
                        StatTile(label: "Rent", value: formatMoney(s.rent, symbol: symbol))
                        StatTile(label: "Day profit", value: formatMoney(s.dayProfit, symbol: symbol),
                                 color: Color(hex: s.dayProfit >= 0 ? StatusPalette.good(cb) : StatusPalette.bad(cb)))
                    }
                    HStack(spacing: 8) {
                        StatTile(label: "Served", value: "\(st.served)")
                        StatTile(label: "Walked out", value: "\(st.angry)",
                                 color: st.angry > 0 ? Color(hex: StatusPalette.bad(cb)) : .white)
                        StatTile(label: "Items sold", value: "\(st.unitsSold)")
                        StatTile(label: "Shoplifters", value: "\(st.caught) caught / \(st.thefts) got away")
                    }
                    HStack(spacing: 8) {
                        StatTile(label: "Out-of-stock", value: "\(st.outOfStock)")
                        StatTile(label: "Too pricey", value: "\(st.tooExpensive)")
                        StatTile(label: "Change errors", value: "\(st.changeMistakes)")
                        StatTile(label: "Cash", value: formatMoney(s.cash, symbol: symbol))
                    }
                    VStack(spacing: 10) {
                        GoalBar(label: "Level profit", current: s.levelProfit, goal: s.profitGoal,
                                text: "\(formatMoney(s.levelProfit, symbol: symbol)) / \(formatMoney(s.profitGoal, symbol: symbol))", colorblind: cb)
                        GoalBar(label: "Store rating", current: s.rating, goal: s.ratingGoal,
                                text: String(format: "%.1f★ / %.1f★", s.rating, s.ratingGoal), colorblind: cb)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: Theme.panel2)))
                    if !st.missing.isEmpty {
                        let top = st.missing.sorted { $0.value > $1.value }.prefix(5)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Customers couldn't find").font(.system(size: 13, weight: .bold))
                            Text(top.map { "\(Catalog.product($0.key)?.name ?? $0.key) ×\($0.value)" }.joined(separator: "  ·  "))
                                .font(.system(size: 13)).foregroundColor(Color(hex: Theme.dim))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: Theme.panel2)))
                    }
                    Button(action: onContinue) {
                        Text(s.isLastDay ? "Back to stores" : "Start day \(s.day + 1)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
}

@MainActor
struct PauseView: View {
    let levelName: String
    let day: Int
    let totalDays: Int
    let onResume: () -> Void
    let onSettings: () -> Void
    let onHelp: () -> Void
    let onRestartDay: () -> Void
    let onQuit: () -> Void
    @State private var confirm: String?

    var body: some View {
        OverlayPanel(title: "Paused", subtitle: "\(levelName) · Day \(day) of \(totalDays)", maxWidth: 420, onClose: onResume) {
            VStack(spacing: 10) {
                Button(action: onResume) { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(BrandButtonStyle())
                Button(action: onSettings) { Label("Settings", systemImage: "gearshape.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(BrandButtonStyle(filled: false))
                Button(action: onHelp) { Label("How to play", systemImage: "questionmark.circle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(BrandButtonStyle(filled: false))
                if confirm == "restart" {
                    Button(action: onRestartDay) { Text("Tap again to restart day \(day)").frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(color: 0xB03A2E))
                } else {
                    Button { confirm = "restart" } label: { Label("Restart day", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(filled: false))
                }
                if confirm == "quit" {
                    Button(action: onQuit) { Text("Quit — today's progress is lost").frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(color: 0xB03A2E))
                } else {
                    Button { confirm = "quit" } label: { Label("Quit to menu", systemImage: "door.left.hand.open").frame(maxWidth: .infinity) }
                        .buttonStyle(BrandButtonStyle(filled: false))
                }
                Text("The game saves at the start of every day.")
                    .font(.system(size: 12)).foregroundColor(Color(hex: Theme.dim))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}
