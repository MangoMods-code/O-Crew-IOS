import SwiftUI

@MainActor
struct SettingsView: View {
    var inGame: Bool
    let onClose: () -> Void
    @ObservedObject private var store = SettingsStore.shared
    @State private var tab = 0

    var body: some View {
        OverlayPanel(title: "Settings", subtitle: inGame ? "Changes apply instantly" : nil, maxWidth: 820, onClose: onClose) {
            VStack(spacing: 8) {
                Picker("", selection: $tab) {
                    Text("Display").tag(0)
                    Text("Controls").tag(1)
                    Text("Game").tag(2)
                    Text("Access & Audio").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                ScrollView {
                    VStack(spacing: 12) {
                        switch tab {
                        case 0: displayTab
                        case 1: controlsTab
                        case 2: gameTab
                        default: accessTab
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: Tabs

    @ViewBuilder private var displayTab: some View {
        Section2("HUD") {
            SliderRow(title: "HUD size", value: $store.display.hudScale, range: 0.7...1.5, format: pct)
            SliderRow(title: "HUD opacity", value: $store.display.hudOpacity, range: 0.3...1, format: pct)
            SliderRow(title: "Text size", value: $store.display.textScale, range: 0.8...1.5, format: pct)
            PickerRow(title: "Currency symbol", selection: $store.display.currencySymbol, options: ["$", "£", "€", "¥", "₩", "₹", "R$", "kr"].map { ($0, $0) })
        }
        Section2("HUD elements") {
            ToggleRow(title: "Show money", isOn: $store.display.showMoney)
            ToggleRow(title: "Show store rating", isOn: $store.display.showRating)
            ToggleRow(title: "Show clock", isOn: $store.display.showClock)
            ToggleRow(title: "24-hour clock", isOn: $store.display.use24hClock)
            ToggleRow(title: "Interaction prompts", isOn: $store.display.showPrompts)
            ToggleRow(title: "Skill & button labels", isOn: $store.display.showSkillLabels)
            ToggleRow(title: "Notifications", isOn: $store.display.showToasts)
            ToggleRow(title: "FPS counter", isOn: $store.display.showFPS)
        }
        Section2("In the world") {
            ToggleRow(title: "Price tags on shelves", isOn: $store.display.showPriceTags)
            ToggleRow(title: "Customer patience bars", isOn: $store.display.showPatienceBars)
            ToggleRow(title: "Money popups at register", isOn: $store.display.showMoneyPopups)
            ToggleRow(title: "Highlight what you're looking at", isOn: $store.display.highlightFocused)
        }
        Section2("Crosshair") {
            PickerRow(title: "Style", selection: $store.display.crosshair, options: CrosshairStyle.allCases.map { ($0, $0.label) })
            PickerRow(title: "Color", selection: $store.display.crosshairColor, options: CrosshairColor.allCases.map { ($0, $0.label) })
            SliderRow(title: "Size", value: $store.display.crosshairSize, range: 0.5...2, format: pct)
        }
        Section2("Camera") {
            SliderRow(title: "Field of view", value: $store.display.fieldOfView, range: 65...110, step: 1, format: { "\(Int($0))°" })
            ToggleRow(title: "Head bob", isOn: $store.display.headBob)
            SliderRow(title: "Camera smoothing", value: $store.display.cameraSmoothing, range: 0...0.8, format: pct)
            PickerRow(title: "Frame rate", selection: $store.display.frameRate, options: FrameRateCap.allCases.map { ($0, $0.label) })
        }
        resetButton("Reset display & controls") { store.resetDisplay() }
    }

    @ViewBuilder private var controlsTab: some View {
        Section2("Layout") {
            ToggleRow(title: "Left-handed (swap stick and buttons)", isOn: $store.display.leftHanded)
            PickerRow(title: "Move stick", selection: $store.display.joystickMode, options: JoystickMode.allCases.map { ($0, $0.label) })
            SliderRow(title: "Stick size", value: $store.display.joystickSize, range: 0.7...1.5, format: pct)
            SliderRow(title: "Button size", value: $store.display.buttonSize, range: 0.7...1.5, format: pct)
        }
        Section2("Interaction") {
            ToggleRow(title: "Tap the world to interact", isOn: $store.display.tapToInteract)
            ToggleRow(title: "Hold Use button to keep stocking", isOn: $store.display.holdToRepeatStock)
        }
        Section2("Look") {
            SliderRow(title: "Look sensitivity", value: $store.display.lookSensitivity, range: 0.3...2.5, format: pct)
            SliderRow(title: "Vertical sensitivity", value: $store.display.lookSensitivityY, range: 0.3...2, format: pct)
            ToggleRow(title: "Invert vertical look", isOn: $store.display.invertY)
        }
    }

    @ViewBuilder private var gameTab: some View {
        Section2("Difficulty") {
            PickerRow(title: "Preset", selection: Binding(
                get: { store.game.difficulty },
                set: { store.game.apply($0) }), options: Difficulty.allCases.map { ($0, $0.label) })
            Text("Changing any rule below switches to Custom. Rules apply from the next day if you're mid-game.")
                .font(.system(size: 12)).foregroundColor(Color(hex: Theme.dim))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        Section2("Day & customers") {
            SliderRow(title: "Day length", value: g(\.dayLengthMinutes), range: 4...25, step: 1, format: { "\(Int($0)) min" })
            SliderRow(title: "Customer traffic", value: g(\.customerRate), range: 0.3...2.5, format: pct)
            SliderRow(title: "Customer patience", value: g(\.customerPatience), range: 0.4...2.5, format: pct)
            SliderRow(title: "Price sensitivity", value: g(\.priceSensitivity), range: 0.3...2.5, format: pct)
            SliderRow(title: "Shoplifters", value: g(\.theftRate), range: 0...3, format: pct)
            SliderRow(title: "Customers paying cash", value: g(\.cashCustomerShare), range: 0...1, format: pct)
            ToggleRow(title: "Shoppers finish at closing time", isOn: g(\.finishShoppersAtClose))
            ToggleRow(title: "Harsh out-of-stock penalty", isOn: g(\.outOfStockPenalty))
        }
        Section2("Economy") {
            SliderRow(title: "Starting cash", value: g(\.startingCash), range: 0.5...3, format: pct)
            SliderRow(title: "Rent", value: g(\.rentMultiplier), range: 0...2, format: pct)
            PickerRow(title: "Delivery speed", selection: g(\.delivery), options: DeliverySpeed.allCases.map { ($0, $0.label) })
        }
        Section2("You") {
            SliderRow(title: "Walk speed", value: g(\.walkSpeed), range: 0.7...1.6, format: pct)
            SliderRow(title: "Skill cooldowns", value: g(\.skillCooldown), range: 0.3...2, format: pct)
        }
        Section2("Checkout & helpers") {
            ToggleRow(title: "Count out cash change yourself", isOn: g(\.manualChange))
            ToggleRow(title: "Show how much change is due", isOn: g(\.showChangeDue))
            ToggleRow(title: "Auto-toss empty boxes", isOn: g(\.autoDiscardEmptyBoxes))
            ToggleRow(title: "Tutorial tips", isOn: g(\.showTutorial))
        }
        resetButton("Reset game rules") { store.resetGame() }
    }

    @ViewBuilder private var accessTab: some View {
        Section2("Accessibility") {
            PickerRow(title: "Colorblind mode", selection: $store.display.colorblind, options: ColorblindMode.allCases.map { ($0, $0.label) })
            ToggleRow(title: "High-contrast HUD", isOn: $store.display.highContrastHUD)
            ToggleRow(title: "Reduce motion", isOn: $store.display.reduceMotion)
            ToggleRow(title: "Haptics", isOn: $store.display.haptics)
        }
        Section2("Audio") {
            SliderRow(title: "Sound effects", value: $store.display.sfxVolume, range: 0...1, format: pct)
        }
        if !inGame {
            Section2("Data") {
                ResetProgressRow()
            }
        }
    }

    // MARK: Helpers

    private func g<T>(_ kp: WritableKeyPath<GameSettings, T>) -> Binding<T> {
        Binding(get: { store.game[keyPath: kp] }, set: {
            store.game[keyPath: kp] = $0
            store.game.difficulty = .custom
        })
    }

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private func resetButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(BrandButtonStyle(filled: false))
    }
}

@MainActor
private struct ResetProgressRow: View {
    @State private var armed = false
    var body: some View {
        Button {
            if armed { ProgressStore.shared.resetAll(); armed = false } else { armed = true }
        } label: {
            Text(armed ? "Tap again to erase ALL progress" : "Reset all progress").frame(maxWidth: .infinity)
        }
        .buttonStyle(BrandButtonStyle(color: 0xB03A2E, filled: armed))
    }
}

// MARK: Rows

@MainActor
struct Section2<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(Color(hex: Theme.brand))
                .padding(.leading, 4)
            VStack(spacing: 2) { content() }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: Theme.panel2)))
        }
    }
}

@MainActor
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) { Text(title).font(.system(size: 15, weight: .medium)) }
            .tint(Color(hex: Theme.brand))
            .padding(.vertical, 3)
    }
}

@MainActor
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.05
    let format: (Double) -> String
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 15, weight: .medium)).frame(width: 190, alignment: .leading)
            Slider(value: $value, in: range, step: step).tint(Color(hex: Theme.brand))
            Text(format(value)).font(.system(size: 14, weight: .bold).monospacedDigit()).frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

@MainActor
struct PickerRow<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .medium))
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { i in
                    Text(options[i].1).tag(options[i].0)
                }
            }
            .pickerStyle(.menu)
            .tint(Color(hex: Theme.brand))
        }
        .padding(.vertical, 1)
    }
}
