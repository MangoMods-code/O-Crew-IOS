import SwiftUI

/// Cash drawer: tap bills and coins to build the customer's change.
@MainActor
struct ChangeView: View {
    let request: ChangeRequest
    let showDue: Bool
    let symbol: String
    let onGive: (Double) -> Void
    let onCancel: () -> Void

    @State private var given: [Double] = []

    private let bills: [Double] = [50, 20, 10, 5, 1]
    private let coins: [Double] = [0.25, 0.10, 0.05, 0.01]

    private var total: Double { (given.reduce(0, +) * 100).rounded() / 100 }
    private var due: Double { ((request.tendered - request.total) * 100).rounded() / 100 }

    var body: some View {
        OverlayPanel(title: "Make Change", subtitle: "Tap money from the drawer, then hand it over", maxWidth: 700, onClose: onCancel) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    StatTile(label: "Total", value: formatMoney(request.total, symbol: symbol))
                    StatTile(label: "They paid", value: formatMoney(request.tendered, symbol: symbol))
                    StatTile(label: "Change due", value: showDue ? formatMoney(due, symbol: symbol) : "?",
                             color: Color(hex: Theme.brand))
                    StatTile(label: "You're giving", value: formatMoney(total, symbol: symbol),
                             color: abs(total - due) < 0.005 ? Color(hex: StatusPalette.good(.off)) : .white)
                }
                .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    ForEach(bills, id: \.self) { b in
                        Button { add(b) } label: {
                            Text(label(b)).font(.system(size: 18, weight: .heavy))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x1E8449)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0x82E0AA).opacity(0.6), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                HStack(spacing: 8) {
                    ForEach(coins, id: \.self) { c in
                        Button { add(c) } label: {
                            Text(label(c)).font(.system(size: 16, weight: .heavy))
                                .frame(width: 64, height: 64)
                                .background(Circle().fill(Color(hex: c == 0.01 ? 0xB9770E : 0x95A5A6)))
                                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button { if !given.isEmpty { given.removeLast() } } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(BrandButtonStyle(filled: false))
                    Button { given.removeAll() } label: { Text("Clear") }
                        .buttonStyle(BrandButtonStyle(filled: false))
                    Button { onGive(total) } label: { Label("Hand over", systemImage: "hand.raised.fill") }
                        .buttonStyle(BrandButtonStyle())
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
        }
    }

    private func add(_ v: Double) {
        given.append(v)
        Feedback.shared.play(.place, volume: 0.4)
        Feedback.shared.haptic(.light)
    }

    private func label(_ v: Double) -> String {
        v >= 1 ? "\(symbol)\(Int(v))" : "\(Int((v * 100).rounded()))¢"
    }
}
