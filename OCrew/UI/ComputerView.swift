import SwiftUI

@MainActor
final class ComputerModel: ObservableObject {
    let world: GameWorld
    @Published var cart: [String: Int] = [:]
    @Published var tab: Int
    @Published var message: String?
    @Published var revision = 0
    let focusProduct: String?

    init(world: GameWorld, focusProduct: String?) {
        self.world = world
        self.focusProduct = focusProduct
        tab = focusProduct == nil ? 0 : 1
    }

    var products: [Product] { world.level.products.compactMap { Catalog.product($0) } }
    var symbol: String { world.symbol }
    var cash: Double { world.cash }
    var cartBoxes: Int { cart.values.reduce(0, +) }
    var cartCost: Double { cart.reduce(0.0) { $0 + (Catalog.product($1.key)?.boxCost ?? 0) * Double($1.value) } }
    var padFree: Int { StoreLayout.padCapacity - world.padBoxes.count - world.pending.count }

    func add(_ id: String, _ n: Int) {
        let v = max(0, (cart[id] ?? 0) + n)
        cart[id] = v == 0 ? nil : v
        message = nil
    }

    func fillLow() {
        let inv = world.inventory()
        for p in products {
            let have = (inv[p.id]?.shelf ?? 0) + (inv[p.id]?.boxed ?? 0)
            if have < p.perBox && (cart[p.id] ?? 0) == 0 { cart[p.id] = 1 }
        }
        message = nil
    }

    func order() {
        if let err = world.placeOrder(cart) {
            message = err
            Feedback.shared.play(.error, volume: 0.5)
        } else {
            message = "Order placed!"
            cart = [:]
        }
        revision += 1
    }

    func price(_ id: String) -> Double { world.prices[id] ?? Catalog.product(id)?.market ?? 0 }

    func setPrice(_ id: String, _ v: Double) {
        world.setPrice(id, v)
        revision += 1
    }

    func bulk(_ factor: Double) {
        for p in products { world.setPrice(p.id, p.market * factor) }
        revision += 1
    }
}

@MainActor
struct ComputerView: View {
    @ObservedObject var model: ComputerModel
    let onClose: () -> Void

    var body: some View {
        OverlayPanel(title: "Store Computer",
                     subtitle: "Cash \(formatMoney(model.cash, symbol: model.symbol))  ·  Loading area space: \(model.padFree) boxes",
                     maxWidth: 820, onClose: onClose) {
            VStack(spacing: 10) {
                Picker("", selection: $model.tab) {
                    Text("Order stock").tag(0)
                    Text("Prices").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                if model.tab == 0 { orderTab } else { priceTab }
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: Order

    private var orderTab: some View {
        let inv = model.world.inventory()
        return VStack(spacing: 8) {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.products) { p in
                        let stock = inv[p.id]
                        HStack(spacing: 10) {
                            ProductSwatch(product: p)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.system(size: 15, weight: .bold))
                                Text("\(p.perBox) per box · \(formatMoney(p.boxCost, symbol: model.symbol)) · \(p.fixture.label)")
                                    .font(.system(size: 12)).foregroundColor(Color(hex: Theme.dim))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("On shelf \(stock?.shelf ?? 0)").font(.system(size: 11, weight: .semibold))
                                Text("In boxes \(stock?.boxed ?? 0)").font(.system(size: 11)).foregroundColor(Color(hex: Theme.dim))
                            }
                            .frame(width: 92, alignment: .trailing)
                            HStack(spacing: 6) {
                                Button { model.add(p.id, -1) } label: { Image(systemName: "minus") }
                                    .buttonStyle(ChipButtonStyle())
                                Text("\(model.cart[p.id] ?? 0)")
                                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                                    .frame(minWidth: 24)
                                Button { model.add(p.id, 1) } label: { Image(systemName: "plus") }
                                    .buttonStyle(ChipButtonStyle(color: Theme.brand))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: Theme.panel2)))
                    }
                }
                .padding(.horizontal, 20)
            }
            HStack(spacing: 10) {
                Button("Add 1 box of anything low") { model.fillLow() }
                    .buttonStyle(BrandButtonStyle(filled: false))
                Button("Clear") { model.cart = [:] }
                    .buttonStyle(BrandButtonStyle(filled: false))
                Spacer()
                if let m = model.message {
                    Text(m).font(.system(size: 13, weight: .semibold))
                        .foregroundColor(m == "Order placed!" ? Color(hex: StatusPalette.good(.off)) : Color(hex: 0xF5B041))
                        .lineLimit(2)
                }
                Button("Buy \(model.cartBoxes) box\(model.cartBoxes == 1 ? "" : "es") · \(formatMoney(model.cartCost, symbol: model.symbol))") {
                    model.order()
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(model.cartBoxes == 0)
                .opacity(model.cartBoxes == 0 ? 0.5 : 1)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Prices

    private var priceTab: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.products) { p in
                            PriceRow(product: p, model: model, highlighted: p.id == model.focusProduct)
                                .id(p.id)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .onAppear {
                    if let f = model.focusProduct {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { proxy.scrollTo(f, anchor: .center) }
                    }
                }
            }
            HStack(spacing: 8) {
                Text("Set all:").font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: Theme.dim))
                Button("−10%") { model.bulk(0.9) }.buttonStyle(ChipButtonStyle())
                Button("Market") { model.bulk(1.0) }.buttonStyle(ChipButtonStyle())
                Button("+10%") { model.bulk(1.1) }.buttonStyle(ChipButtonStyle())
                Button("+20%") { model.bulk(1.2) }.buttonStyle(ChipButtonStyle())
                Spacer()
                Text("Shoppers walk away from prices well above market.")
                    .font(.system(size: 12)).foregroundColor(Color(hex: Theme.dim)).lineLimit(2)
            }
            .padding(.horizontal, 20)
        }
    }
}

@MainActor
struct PriceRow: View {
    let product: Product
    @ObservedObject var model: ComputerModel
    let highlighted: Bool

    var body: some View {
        let price = model.price(product.id)
        let margin = price > 0 ? (price - product.cost) / price * 100 : 0
        let ratio = price / product.market
        let tone: UInt32 = ratio <= 1.0 ? StatusPalette.good(.off) : ratio <= 1.2 ? StatusPalette.warn(.off) : StatusPalette.bad(.off)
        return HStack(spacing: 10) {
            ProductSwatch(product: product)
            VStack(alignment: .leading, spacing: 1) {
                Text(product.name).font(.system(size: 15, weight: .bold))
                Text("Cost \(formatMoney(product.cost, symbol: model.symbol)) · Market \(formatMoney(product.market, symbol: model.symbol)) · Margin \(Int(margin))%")
                    .font(.system(size: 12)).foregroundColor(Color(hex: Theme.dim))
            }
            Spacer()
            HStack(spacing: 5) {
                Button("−1") { model.setPrice(product.id, price - 1) }.buttonStyle(ChipButtonStyle())
                Button("−.10") { model.setPrice(product.id, price - 0.1) }.buttonStyle(ChipButtonStyle())
                Text(formatMoney(price, symbol: model.symbol))
                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                    .foregroundColor(Color(hex: tone))
                    .frame(minWidth: 70)
                Button("+.10") { model.setPrice(product.id, price + 0.1) }.buttonStyle(ChipButtonStyle())
                Button("+1") { model.setPrice(product.id, price + 1) }.buttonStyle(ChipButtonStyle())
                Button("Mkt") { model.setPrice(product.id, product.market) }.buttonStyle(ChipButtonStyle(color: 0x1F618D))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: highlighted ? 0x2E3A48 : Theme.panel2)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(highlighted ? Color(hex: Theme.brand) : Color.clear, lineWidth: 2))
    }
}
