import Foundation
import StoreKit
import SwiftUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published var data: LocalData {
        didSet {
            guard ready, data != oldValue else { return }
            if dataReadable { storage.save(data, onError: storageError) }
            if data.staples != oldValue.staples || data.pinned != oldValue.pinned || data.draft.currency != oldValue.draft.currency {
                syncWidget()
            }
        }
    }
    @Published private(set) var entitlement = Entitlement(firstOpen: .now)
    @Published private(set) var ready = false
    @Published private(set) var now = Date()
    @Published private(set) var products: [Product] = []
    @Published private(set) var busy = false
    @Published var storeMessage: String?
    @Published var storageFailed = false
    @Published var reviewAttempts = 0

    let locale = Locale.current
    private let storage = Storage(testing: Launch.uiTesting)
    private var dataReadable = true
    private var clock = ProcessInfo.processInfo.systemUptime
    private var clockAnchor = Date()
    private var widgetSnapshot: WidgetSnapshot?
    private var started = false
    private var observation: Task<Void, Never>?

    static let currencies = ["USD", "CNY", "HKD", "TWD", "JPY", "CAD", "AUD", "GBP", "EUR", "SGD", "KRW", "MYR", "NZD", "CHF", "INR", "MXN", "BRL"]

    init() {
        let localCurrency = Locale.current.currency?.identifier ?? "USD"
        let currency = Self.currencies.contains(localCurrency) ? localCurrency : "USD"
        data = LocalData(draft: .blank(currency: currency, unit: currency == "USD" ? .oz : .g))
    }

    var hasPro: Bool { entitlement.hasPro(at: currentTime) }
    var hasPurchased: Bool { entitlement.purchasedPro }
    var activeItems: [ShelfItem] { hasPro ? data.draft.items : Array(data.draft.items.prefix(2)) }
    var currency: String { data.draft.currency }

    func effectiveItem(_ item: ShelfItem) -> ShelfItem {
        guard !hasPro, item.offer.kind != .regular else { return item }
        var regular = item
        regular.offer = Offer()
        regular.packs = 1
        return regular
    }

    var quotes: [Quote] { activeItems.compactMap { effectiveItem($0).quote(locale: locale) } }
    var comparison: Comparison { Comparison(quotes) }

    func display(for unit: ShelfUnit) -> DisplayUnit {
        if let display = data.draft.display, display.unit.dimension == unit.dimension { return display }
        return .standard(for: unit, imperial: data.draft.imperial)
    }

    func unitPrice(_ quote: Quote, display: DisplayUnit? = nil, currency: String? = nil) -> String {
        let basis = display ?? self.display(for: quote.unit)
        let amount = quote.rate * basis.factor
        let precision = amount > 0 && amount < Decimal(string: "0.01")! ? 6 : 3
        return L.f("price.per", L.money(amount, code: currency ?? self.currency, precision: precision), basis.label)
    }

    func clear() {
        let last = data.draft.lastUnit
        var draft = ComparisonDraft.blank(currency: currency, unit: last ?? (data.draft.imperial ? .oz : .g))
        draft.lastUnit = last
        data.draft = draft
    }

    func setUnit(_ unit: ShelfUnit, for id: UUID, ply: Int? = nil) {
        data.draft.setUnit(unit, for: id, ply: ply)
    }

    func addItem() -> UUID? {
        guard hasPro, data.draft.items.count < 10,
              let letter = (0..<10).first(where: { letter in !data.draft.items.contains { $0.letter == letter } }) else { return nil }
        let item = ShelfItem(letter: letter, unit: data.draft.items.first!.unit)
        data.draft.items.append(item)
        return item.id
    }

    func savePrice(to definition: StapleDefinition, entry: PriceEntry) -> UUID? {
        guard hasPro, definition.isValid, definition.unit.dimension == entry.quote.unit.dimension else { return nil }
        var updated = data
        if let index = updated.staples.firstIndex(where: { $0.definition.key == definition.key }) {
            updated.staples[index].entries.append(entry)
            data = updated
            return updated.staples[index].id
        }
        guard updated.staples.count < ListCode.maxItems else { return nil }
        let staple = Staple(definition: definition, entries: [entry])
        updated.staples.append(staple)
        data = updated
        return staple.id
    }

    @discardableResult
    func importList(_ definitions: [StapleDefinition]) -> Bool {
        var updated = data
        updated.merge(definitions)
        guard updated.staples.count <= ListCode.maxItems else { return false }
        data = updated
        return true
    }

    func logPurchase(chosen: Quote, alternative: Quote) {
        guard let item = activeItems.first(where: { $0.id == chosen.id }) else { return }
        let date = currentTime
        data.log(PurchaseLog(id: data.draft.id, date: date, day: DayKey.local(date), currency: currency,
                             item: effectiveItem(item), baseline: alternative, actual: chosen, display: display(for: chosen.unit)))
    }

    var currentTime: Date {
        if Launch.uiTesting { return now }
        return max(Date(), clockAnchor.addingTimeInterval(ProcessInfo.processInfo.systemUptime - clock))
    }

    func tick() {
        let current = currentTime
        now = current
        guard ready else { return }
        if entitlement.highWater == nil || current.timeIntervalSince(entitlement.highWater ?? current) >= 60 {
            var updated = entitlement
            updated.observe(current)
            entitlement = updated
            storage.updateEntitlement(updated, onError: storageError)
        }
        syncWidget()
    }

    func recordReviewUse() {
        guard ready, comparison.ready, !Launch.uiTesting || Launch.testFlag("-review-demo") else { return }
        data.review.record(entitlement.effectiveDate(currentTime))
    }

    func start() async {
        guard !started else { return }
        started = true
        let loaded = await storage.load(defaults: data, now: now, reset: Launch.testFlag("-reset"))
        data = loaded.data
        dataReadable = loaded.dataReadable
        storageFailed = loaded.hadError
        entitlement = loaded.entitlement
        clockAnchor = entitlement.effectiveDate(.now)
        clock = ProcessInfo.processInfo.systemUptime
        if Launch.uiTesting { prepareTestData() }
        ready = true
        syncWidget()
        guard !Launch.uiTesting, !Launch.isFree else { return }
        observation = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { break }
                await self.consume(result)
            }
        }
        await refreshEntitlements()
    }

    deinit { observation?.cancel() }

    private func prepareTestData() {
        if Launch.testFlag("-expired") || Launch.testFlag("-paywall") {
            entitlement = Entitlement(firstOpen: now.addingTimeInterval(-31 * 86_400))
        }
        if Launch.testFlag("-purchased") { entitlement.purchasedPro = true }
        if Launch.testFlag("-review-demo") {
            let calendar = Calendar.current
            data.review.record(calendar.date(byAdding: .day, value: -2, to: now) ?? now)
            data.review.record(calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        }
        if Launch.testFlag("-demo") || Launch.testFlag("-demo-convert") || Launch.testFlag("-demo-offer") ||
            Launch.testFlag("-demo-history") || Launch.testFlag("-demo-share") {
            data = .demo(now: now, locale: locale)
        }
        if Launch.testFlag("-demo-convert") {
            data.draft.items[1].unit = .lb
            data.draft.items[1].size = "2"
        }
        if Launch.testFlag("-demo-offer") {
            data.draft.items[1].price = L.number(Decimal(string: "3.79")!, digits: 2, minimum: 2)
            data.draft.items[1].size = "12"
            data.draft.items[1].packs = 2
            data.draft.items[1].offer = Offer(kind: .bundle, total: 5)
        }
        if Launch.testFlag("-milestone-demo"), let item = data.draft.items.last, let actual = item.quote(locale: locale) {
            let date = now.addingTimeInterval(-86_400)
            var baseline = actual
            baseline.id = UUID()
            baseline.cost += 49
            data.purchases.append(PurchaseLog(id: UUID(), date: date, day: DayKey.local(date), currency: "USD",
                                              item: item, baseline: baseline, actual: actual, display: .oz))
        }
    }

    private var storageError: @Sendable () -> Void {
        { [weak self] in Task { @MainActor in self?.storageFailed = true } }
    }

    private func syncWidget() {
        guard ready, !Launch.uiTesting else { return }
        let staple = data.staples.first { $0.id == data.pinned }
        let snapshot = WidgetSnapshot(entitlement: entitlement, name: staple?.definition.name, staple: staple?.id,
                                      low: hasPro ? staple?.lowest(currency: currency) : nil)
        guard snapshot != widgetSnapshot else { return }
        let old = widgetSnapshot
        widgetSnapshot = snapshot
        let reload = old?.low != snapshot.low || old?.name != snapshot.name || old?.staple != snapshot.staple ||
            old?.entitlement.trialEnd != snapshot.entitlement.trialEnd ||
            old?.entitlement.purchasedPro != snapshot.entitlement.purchasedPro
        storage.updateWidget(snapshot) {
            if reload { WidgetCenter.shared.reloadTimelines(ofKind: "UnitPriceWidget") }
        }
    }

    func loadProducts() async {
        guard !Launch.uiTesting, !Launch.isFree, products.isEmpty else { return }
        do {
            products = try await Product.products(for: [Launch.proID, Launch.trialID])
        } catch {
            storeMessage = L.t("store.unavailable")
        }
    }

    func buy(_ id: String) async {
        guard !busy, !Launch.uiTesting else { return }
        busy = true
        storeMessage = nil
        defer { busy = false }
        await loadProducts()
        guard let product = products.first(where: { $0.id == id }) else {
            storeMessage = L.t("store.unavailable")
            return
        }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await consume(result)
            case .pending:
                storeMessage = L.t("store.pending")
            case .userCancelled:
                break
            @unknown default:
                storeMessage = L.t("store.unavailable")
            }
        } catch {
            storeMessage = L.t("store.unavailable")
        }
    }

    func restore() async {
        guard !busy, !Launch.uiTesting else { return }
        busy = true
        storeMessage = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements(authoritative: true)
            storeMessage = entitlement.purchasedPro || entitlement.trialReceiptAt != nil
                ? L.t("store.restored") : L.t("store.none")
        } catch {
            storeMessage = L.t("store.unavailable")
        }
    }

    private func consume(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else {
            storeMessage = L.t("store.unverified")
            return
        }
        guard transaction.productID == Launch.proID || transaction.productID == Launch.trialID else { return }
        var updated = entitlement
        if transaction.productID == Launch.proID {
            updated.purchasedPro = transaction.revocationDate == nil
        } else if transaction.revocationDate == nil {
            updated.applyTrialReceipt(transaction.originalPurchaseDate)
        }
        updateEntitlement(updated)
        await transaction.finish()
    }

    private func refreshEntitlements(authoritative: Bool = false) async {
        var foundPro = false
        var trial: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if transaction.productID == Launch.proID { foundPro = true }
            if transaction.productID == Launch.trialID {
                trial = min(trial ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
            }
        }
        let latest = await StoreKit.Transaction.latest(for: Launch.proID)
        var updated = entitlement
        if case .verified(let transaction)? = latest {
            updated.purchasedPro = transaction.revocationDate == nil
        } else if foundPro || authoritative {
            updated.purchasedPro = foundPro
        }
        if let trial { updated.applyTrialReceipt(trial) }
        updateEntitlement(updated)
    }

    private func updateEntitlement(_ value: Entitlement) {
        guard value != entitlement else { return }
        entitlement = value
        storage.updateEntitlement(value, onError: storageError)
        syncWidget()
    }
}

extension LocalData {
    static func demo(now: Date, locale: Locale) -> LocalData {
        func price(_ string: String) -> String {
            let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
            return L.number(value, digits: 2, minimum: 2)
        }
        var draft = ComparisonDraft.blank(currency: "USD", unit: .oz)
        draft.items[0].price = price("4.49")
        draft.items[0].size = "18"
        draft.items[1].price = price("5.99")
        draft.items[1].size = "32"
        var earlier = draft.items[1]
        earlier.price = price("6.39")
        let entry = PriceEntry(date: now.addingTimeInterval(-7 * 86_400), currency: "USD",
                               item: earlier, quote: earlier.quote(locale: locale)!, display: .oz)
        let staple = Staple(definition: StapleDefinition(name: L.t("sample.oats"), unit: .oz), entries: [entry])
        return LocalData(draft: draft, staples: [staple])
    }
}
