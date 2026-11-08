import SceneKit
import simd

extension GameWorld {
    // MARK: Day flow

    func beginDay() {
        phase = .prep
        clock = 0
        stats = DayStats()
        skills.reset()
        rushAnnounced = []
        updateSign()
        snapshot()
        if !tutorialActive {
            toast("Day \(day) of \(level.days) — stock up, then flip the sign to OPEN", .info)
        }
    }

    func openStore() {
        guard phase == .prep else { return }
        phase = .open
        updateSign()
        Feedback.shared.play(.chime)
        toast("We're open!", .good)
        spawnCustomer()
    }

    func beginClosing(early: Bool) {
        guard phase == .open else { return }
        phase = .closing
        updateSign()
        toast(early ? "Closed early — finish serving who's inside" : "8 PM — store's closed. Finish serving who's inside", .info)
        if !game.finishShoppersAtClose {
            for c in customers where [.entering, .toShelf, .picking].contains(c.state) {
                if c.basket.isEmpty { leave(c, angry: false) } else { finishShopping(c) }
            }
        }
    }

    func endDay() {
        guard phase == .closing else { return }
        phase = .ended
        let rent = (level.dailyRent * game.rentMultiplier).rounded()
        cash -= rent
        stats.expenses += rent
        let dayProfit = stats.revenue - stats.expenses
        levelProfit += dayProfit
        let isLast = day >= level.days
        let passed = levelProfit >= level.profitGoal && rating >= level.ratingGoal
        var stars = 0
        if passed {
            stars = 1
            if levelProfit >= level.profitGoal * 1.5 { stars = 2 }
            if levelProfit >= level.profitGoal * 2 && rating >= level.ratingGoal + 0.6 { stars = 3 }
        }
        let summary = DaySummary(
            levelName: level.name, day: day, totalDays: level.days, stats: stats, rent: rent,
            dayProfit: dayProfit, levelProfit: levelProfit, profitGoal: level.profitGoal,
            rating: rating, ratingGoal: level.ratingGoal, cash: cash, isLastDay: isLast,
            passed: passed, stars: stars, nextLevelName: Levels.next(after: level.id)?.name)
        lastSummary = summary
        Feedback.shared.play(isLast && passed ? .fanfare : .chime)
        onDayEnded?(summary)
    }

    /// Called when the player dismisses the day summary. Returns false when the level is over.
    func continueAfterSummary() -> Bool {
        guard let s = lastSummary else { return true }
        if s.isLastDay {
            if s.passed {
                ProgressStore.shared.complete(level: level.id, stars: s.stars, profit: s.levelProfit)
            } else {
                ProgressStore.shared.clearSave(level.id)
            }
            return false
        }
        day += 1
        beginDay()
        return true
    }

    // MARK: Saving

    /// Saves the store as it is now, as the start-of-day checkpoint.
    func snapshot() {
        var boxes: [BoxSave] = floorBoxes.map { BoxSave(product: $0.product, count: $0.count) }
        if let c = carried, c.count > 0 { boxes.append(BoxSave(product: c.product, count: c.count)) }
        for p in pending { boxes.append(BoxSave(product: p.product, count: Catalog.product(p.product)?.perBox ?? 0)) }
        let save = LevelSave(
            levelID: level.id, day: day, cash: cash, rating: rating, levelProfit: levelProfit, prices: prices,
            slots: fixtures.map { f in f.slots.map { SlotSave(product: $0.product, count: $0.count) } },
            boxes: Array(boxes.prefix(StoreLayout.padCapacity)))
        ProgressStore.shared.store(save)
    }

    // MARK: Tutorial

    var tutorialText: String? {
        guard tutorialActive else { return nil }
        switch tutorialStep {
        case 0: return "Walk to the computer on the desk near the register and order a few boxes of stock."
        case 1: return "Your delivery lands in the yellow LOADING area by the door. Walk over and tap a box to pick it up."
        case 2: return "Look at an empty shelf and tap to stock it, one item per tap (hold the hand button to go faster). Cold items go in fridges and freezers."
        case 3: return "Nice! Stock a few more, then flip the sign above the door to OPEN."
        case 4: return "Customers queue at the counter. Tap each item on the counter to scan it, then take payment at the register (cash) or card reader."
        default: return nil
        }
    }

    func updateTutorial() {
        guard tutorialActive else { return }
        switch tutorialStep {
        case 0: if ordersPlaced > 0 { tutorialStep = 1 }
        case 1: if carried != nil { tutorialStep = 2 }
        case 2: if stockedUnits >= 3 { tutorialStep = 3 }
        case 3: if phase != .prep { tutorialStep = 4 }
        case 4:
            if stats.served >= 1 {
                tutorialStep = 5
                tutorialActive = false
                ProgressStore.shared.markTutorialSeen()
                toast("Tutorial done! Keep the shelves full and the line moving.", .good)
            }
        default: tutorialActive = false
        }
    }
}
