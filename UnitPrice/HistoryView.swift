import SwiftUI

@MainActor
struct SavePriceSheet: View {
    @ObservedObject var model: AppModel
    let report: (String) -> Void
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                SheetTitle(title: L.t("save.price"), id: "save.title")
                if let quote = model.comparison.lowest,
                   let item = model.activeItems.first(where: { $0.id == quote.id }) {
                    let display = model.display(for: item.unit)
                    Text(model.unitPrice(quote, display: display)).font(.headline.monospacedDigit())
                    ForEach(model.data.staples.filter { $0.definition.unit.dimension == quote.unit.dimension }) { staple in
                        Action(title: staple.definition.name, id: "save.existing.\(staple.id)", fill: true) {
                            write(staple.definition, item: item, quote: quote, display: display)
                        }.ticket()
                    }
                    TextField(L.t("save.name"), text: $name)
                        .padding(9).frame(minHeight: 44).ticket()
                        .accessibilityLabel(L.t("save.name")).accessibilityIdentifier("save.name")
                    let definition = StapleDefinition(name: name.trimmingCharacters(in: .whitespacesAndNewlines), unit: quote.unit)
                    Action(title: L.t("save.price"), id: "save.confirm", primary: true, fill: true) {
                        write(definition, item: item, quote: quote, display: display)
                    }.disabled(!definition.isValid || !model.hasPro)
                }
            }.padding(16)
        }
        .background(Palette.paper)
    }

    private func write(_ definition: StapleDefinition, item: ShelfItem, quote: Quote, display: DisplayUnit) {
        let date = model.currentTime
        let low = model.data.staples.first { $0.definition.key == definition.key }?.lowest(currency: model.currency, before: date)
        let entry = PriceEntry(date: date, currency: model.currency, item: item, quote: quote, display: display)
        guard model.savePrice(to: definition, entry: entry) != nil else {
            report(L.t("save.failed"))
            dismiss()
            return
        }
        report(low.map { HistoryLabels.change(entry.quote, from: $0.quote) } ?? L.t("saved.first"))
        dismiss()
    }
}

enum HistoryLabels {
    static func change(_ today: Quote, from previous: Quote) -> String {
        let current = today.cost * previous.quantity
        let old = previous.cost * today.quantity
        if current == old { return L.t("history.same") }
        if old == 0 { return L.t("history.aboveFree") }
        let percent = abs(current / old - 1) * 100
        let text = percent < Decimal(string: "0.1")! ? L.t("result.lessThan") : L.number(percent, digits: 1)
        return L.f(current < old ? "history.less" : "history.more", text)
    }

    static func condition(_ entry: PriceEntry) -> String {
        L.f("history.condition", entry.item.offer.kind.label, entry.quote.packs)
    }
}

@MainActor
struct HistoryView: View {
    @ObservedObject var model: AppModel
    let stapleID: UUID
    let back: () -> Void
    let pro: () -> Void
    let report: (String) -> Void
    @State private var today: ShelfItem?
    @State private var editing: PriceEntry?
    @State private var deleted: PriceEntry?
    @State private var captured: PriceEntry?
    @State private var savedChange: String?
    @FocusState private var priceFocused: Bool

    private var currentStaple: Staple? { model.data.staples.first { $0.id == stapleID } }
    private var todayQuote: Quote? { today?.quote(locale: model.locale) }

    var body: some View {
        if let staple = currentStaple {
            VStack(spacing: 0) {
                HStack {
                    Action(title: L.t("back"), id: "history.back", icon: "chevron.left", run: back)
                    Spacer(minLength: 3)
                    if model.hasPro {
                        Action(title: L.t(model.data.pinned == stapleID ? "widget.unpin" : "widget.pin"),
                               id: "history.pin", icon: "pin") {
                            model.data.pinned = model.data.pinned == stapleID ? nil : stapleID
                        }
                    }
                }.padding(.horizontal, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(staple.definition.name).font(.title.bold()).accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("history.title")
                        if model.hasPro {
                            comparison(staple)
                            if let savedChange { Text(savedChange).note().accessibilityIdentifier("history.saved") }
                        } else {
                            Action(title: L.t("paywall.history"), id: "history.pro", run: pro)
                        }
                        Text(L.t("history.entries")).font(.headline)
                        if staple.entries.isEmpty { Text(L.t("history.empty")).note() }
                        ForEach(staple.entries.sorted { $0.date > $1.date }) { entry in
                            historyRow(entry)
                        }
                        if model.hasPro, deleted != nil {
                            Action(title: L.t("undo"), id: "history.undo") {
                                if let deleted, let index { model.data.staples[index].entries.append(deleted) }
                                deleted = nil
                            }
                        }
                    }.padding(.horizontal, 15).padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .task(id: stapleID) {
                if today == nil { prepare(staple) }
                guard model.hasPro, !Launch.testFlag("-demo-history") else { return }
                do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
                priceFocused = true
            }
            .sheet(item: $editing) { entry in
                HistoryEditor(model: model, stapleID: stapleID, entry: entry) { value in
                    guard let index, let row = model.data.staples[index].entries.firstIndex(where: { $0.id == value.id }) else { return }
                    model.data.staples[index].entries[row] = value
                } remove: {
                    guard model.hasPro, let index else { return }
                    deleted = entry
                    model.data.staples[index].entries.removeAll { $0.id == entry.id }
                }
            }
        }
    }

    private var index: Int? { model.data.staples.firstIndex { $0.id == stapleID } }

    private func prepare(_ staple: Staple) {
        let latest = staple.entries.filter { $0.currency == model.currency }.max { $0.date < $1.date }
            ?? staple.entries.max { $0.date < $1.date }
        var item = latest?.item ?? ShelfItem(letter: 0, unit: staple.definition.unit)
        item.offer = Offer()
        item.packs = 1
        item.price = Launch.testFlag("-demo-history") ? L.number(Decimal(string: "5.99")!, minimum: 2) : ""
        today = item
    }

    private func input(_ key: String, field: WritableKeyPath<ShelfItem, String>, price: Bool = false) -> some View {
        let binding = Binding(get: { today?[keyPath: field] ?? "" }, set: { text in
            guard text.utf8.count <= 64 else { return }
            today?[keyPath: field] = text
            savedChange = nil
        })
        return VStack(alignment: .leading, spacing: 3) {
            Text(L.t(key)).note()
            if price {
                TextField("—", text: binding).focused($priceFocused)
                    .keyboardType(.decimalPad).padding(8).frame(minHeight: 44).ticket()
                    .accessibilityLabel(L.t(key)).accessibilityIdentifier("history.price")
            } else {
                TextField("—", text: binding)
                    .keyboardType(.decimalPad).padding(8).frame(minHeight: 44).ticket()
                    .accessibilityLabel(L.t(key)).accessibilityIdentifier("history.\(key)")
            }
        }.frame(maxWidth: .infinity)
    }

    private func comparison(_ staple: Staple) -> some View {
        let low = staple.lowest(currency: model.currency, before: model.currentTime,
                                excluding: savedChange == nil ? nil : captured?.id)
        let display = low?.display ?? DisplayUnit.standard(for: staple.definition.unit, imperial: model.data.draft.imperial)
        return VStack(alignment: .leading, spacing: 6) {
            Text(L.f("history.today", model.currency)).font(.headline)
            HStack(spacing: 6) {
                input("field.price", field: \.price, price: true)
                input(today?.paperPly != nil ? "field.rolls" : "field.size", field: \.size)
            }
            if let item = today {
                if item.paperPly != nil && item.unit != .rolls {
                    input("field.sheets", field: \.sheetsPerRoll)
                    Text(L.f("paper.ply", item.paperPly ?? 1)).note()
                }
                if item.paperPly != nil {
                    Text(item.unit.label).note()
                } else {
                    Picker(L.t("display.title"), selection: Binding(get: { today?.unit ?? item.unit }, set: { unit in
                        today?.unit = unit; savedChange = nil
                    })) {
                        ForEach(ShelfUnit.allCases.filter { $0.dimension == item.unit.dimension }, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).accessibilityIdentifier("history.unit")
                }
            }
            if let todayQuote {
                Text(model.unitPrice(todayQuote, display: display)).font(.headline.monospacedDigit())
                    .accessibilityIdentifier("history.current")
            }
            if let low {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("history.low")).note()
                    Text(model.unitPrice(low.quote, display: display, currency: low.currency)).font(.headline.monospacedDigit())
                        .accessibilityIdentifier("history.low")
                    Text(low.date, style: .date).note()
                    Text(HistoryLabels.condition(low)).note()
                }
                if let todayQuote {
                    Text(HistoryLabels.change(todayQuote, from: low.quote)).font(.subheadline.bold())
                        .accessibilityIdentifier("history.delta")
                }
            }
            Action(title: L.t("save.price"), id: "history.save", primary: true, fill: true) {
                guard model.hasPro, let today, let todayQuote else { return }
                let entry = PriceEntry(date: model.currentTime, currency: model.currency, item: today,
                                       quote: todayQuote, display: display)
                if model.savePrice(to: staple.definition, entry: entry) != nil {
                    captured = entry
                    savedChange = low.map { HistoryLabels.change(todayQuote, from: $0.quote) } ?? L.t("saved.first")
                } else { report(L.t("save.failed")) }
                priceFocused = false
            }.disabled(todayQuote == nil || savedChange != nil)
        }
        .padding(10).ticket()
    }

    private func historyRow(_ entry: PriceEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.date, style: .date).font(.subheadline.weight(.semibold))
                Spacer()
                Text(L.money(entry.quote.cost, code: entry.currency)).monospacedDigit()
                if model.hasPro {
                    Action(title: L.t("edit"), id: "history.edit.\(entry.id)") { editing = entry }
                }
            }
            let size = entry.item.paperPly == nil ? entry.item.unit.label : ShelfUnit.rolls.label
            Text(L.f("history.size", entry.item.size, size, entry.item.price, entry.currency)).note()
            if let ply = entry.item.paperPly, !entry.item.sheetsPerRoll.isEmpty {
                Text(L.f("history.paper", entry.item.sheetsPerRoll, ply)).note()
            }
            Text(HistoryLabels.condition(entry)).note()
            Text(model.unitPrice(entry.quote, display: entry.display, currency: entry.currency)).note()
        }.padding(8).ticket()
    }
}

@MainActor
struct HistoryEditor: View {
    @ObservedObject var model: AppModel
    let stapleID: UUID
    let entry: PriceEntry
    let save: (PriceEntry) -> Void
    let remove: () -> Void
    @State private var item: ShelfItem
    @State private var groupTotal: String
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, stapleID: UUID, entry: PriceEntry, save: @escaping (PriceEntry) -> Void, remove: @escaping () -> Void) {
        self.model = model
        self.stapleID = stapleID
        self.entry = entry
        self.save = save
        self.remove = remove
        _item = State(initialValue: entry.item)
        _groupTotal = State(initialValue: L.number(entry.item.offer.total, digits: 8))
    }

    private var revised: PriceEntry? {
        var edited = item
        if [.bundle, .perPack].contains(edited.offer.kind) {
            guard let total = MoneyInput.parse(groupTotal, locale: model.locale), total >= 0 else { return nil }
            edited.offer.total = total
        }
        guard let quote = edited.quote(locale: model.locale) else { return nil }
        var result = entry
        result.item = edited
        result.quote = quote
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                SheetTitle(title: L.t("history.edit"), id: "history.editTitle")
                input("field.price", value: $item.price)
                input(item.paperPly != nil ? "field.rolls" : "field.size", value: $item.size)
                if item.paperPly != nil && item.unit != .rolls { input("field.sheets", value: $item.sheetsPerRoll) }
                if [.bundle, .perPack].contains(item.offer.kind) { input("offer.total", value: $groupTotal) }
                Action(title: L.t("save"), id: "history.editSave", primary: true, fill: true) {
                    if model.hasPro, let revised { save(revised); dismiss() }
                }.disabled(revised == nil || !model.hasPro)
                Action(title: L.t("delete"), id: "history.delete", fill: true) {
                    if model.hasPro { remove(); dismiss() }
                }
            }.padding(16)
        }.background(Palette.paper)
    }

    private func input(_ key: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L.t(key)).note()
            TextField(L.t(key), text: value).keyboardType(.decimalPad)
                .padding(8).frame(minHeight: 44).ticket().accessibilityIdentifier("history.edit.\(key)")
        }
    }
}
