import SwiftUI

/// Dimmed backdrop + dark card used by every in-game overlay.
@MainActor
struct OverlayPanel<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var maxWidth: CGFloat = 760
    var onClose: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 22, weight: .heavy)).foregroundColor(Color(hex: Theme.text))
                        if let s = subtitle {
                            Text(s).font(.system(size: 13, weight: .medium)).foregroundColor(Color(hex: Theme.dim))
                        }
                    }
                    Spacer()
                    if let onClose = onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)
                content()
            }
            .frame(maxWidth: maxWidth)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color(hex: Theme.panel)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.08)))
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }
}

struct BrandButtonStyle: ButtonStyle {
    var color: UInt32 = Theme.brand
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .padding(.vertical, 11)
            .padding(.horizontal, 18)
            .frame(minWidth: 44)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(filled ? Color(hex: color) : Color.white.opacity(0.1))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct ChipButtonStyle: ButtonStyle {
    var color: UInt32 = Theme.panel2
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
            .padding(.vertical, 7)
            .padding(.horizontal, 11)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: color)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

@MainActor
struct ProductSwatch: View {
    let product: Product
    var size: CGFloat = 30
    var body: some View {
        Image(uiImage: Models.labelImage(for: product))
            .resizable()
            .interpolation(.none)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.15)))
    }
}

@MainActor
struct StatTile: View {
    let label: String
    let value: String
    var color: Color = .white
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: Theme.dim))
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: Theme.panel2)))
    }
}

@MainActor
struct GoalBar: View {
    let label: String
    let current: Double
    let goal: Double
    let text: String
    let colorblind: ColorblindMode
    var body: some View {
        let frac = goal > 0 ? max(0, min(1, current / goal)) : 0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 13, weight: .bold))
                Spacer()
                Text(text).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundColor(Color(hex: Theme.dim))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(Color(hex: frac >= 1 ? StatusPalette.good(colorblind) : Theme.brand))
                        .frame(width: max(6, g.size.width * frac))
                }
            }
            .frame(height: 9)
        }
    }
}

@MainActor
struct StarsView: View {
    let count: Int
    var size: CGFloat = 22
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < count ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundColor(i < count ? Color(hex: 0xF4D03F) : Color.white.opacity(0.3))
            }
        }
    }
}
