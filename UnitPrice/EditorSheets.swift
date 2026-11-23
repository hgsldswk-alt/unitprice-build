import SwiftUI

@MainActor
struct UnitSheet: View {
    @ObservedObject var model: AppModel
    let id: UUID
    let didChoose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var customPly = false
    @State private var plyText = ""
    @FocusState private var plyFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let name = model.activeItems.first { $0.id == id }?.name ?? ""
                SheetTitle(title: L.f("unit.title", name), id: "unit.title")
                group("dimension.weight", units: [.oz, .lb, .g, .kg])
                group("dimension.volume", units: [.ml, .l, .floz])
                group("dimension.count", units: [.count, .sheets, .rolls])
                Text(L.t("paper.title")).font(.headline)
                options {
                    ForEach(1...4, id: \.self) { ply in
                        Action(title: L.f("paper.ply", ply), id: "unit.ply.\(ply)") { choose(.layers, ply: ply) }.ticket()
                    }
                    Action(title: L.t("paper.other"), id: "unit.ply.other") {
                        customPly = true
                        plyFocused = true
                    }.ticket()
                }
                if customPly {
                    TextField(L.t("paper.custom"), text: $plyText)
                        .keyboardType(.numberPad).focused($plyFocused)
                        .padding(10).frame(minHeight: 44).ticket()
                        .accessibilityIdentifier("unit.customPly")
                        .onAppear { plyFocused = true }
                        .onChange(of: plyText) { _, text in
                            if let value = Int(text), (5...9).contains(value) { choose(.layers, ply: value) }
                        }
                }
                if let ply = model.activeItems.first(where: { $0.id == id })?.paperPly {
                    Text(L.t("paper.basis")).font(.headline)
                    options {
                        ForEach([ShelfUnit.rolls, .sheets, .layers], id: \.self) { unit in
                            Action(title: unit.label, id: "paper.basis.\(unit.rawValue)") { choose(unit, ply: ply) }.ticket()
                        }
                    }
                }
                Text(L.t("paper.hint")).note()
            }
            .padding(16)
        }
        .background(Palette.paper)
        .presentationDragIndicator(.visible)
    }

    private func group(_ label: String, units: [ShelfUnit]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L.t(label)).font(.headline)
            options {
                ForEach(units, id: \.self) { unit in
                    Action(title: unit.label, id: "unit.choose.\(unit.rawValue)") { choose(unit) }.ticket()
                }
            }
        }
    }

    private func options<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 4, alignment: .leading)],
                  alignment: .leading, spacing: 4, content: content)
    }

    private func choose(_ unit: ShelfUnit, ply: Int? = nil) {
        model.setUnit(unit, for: id, ply: ply)
        didChoose()
        dismiss()
    }
}

@MainActor
struct OfferSheet: View {
    @ObservedObject var model: AppModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var kind: OfferKind
    @State private var total: String
    @State private var paid: String
    @State private var free: String
    @State private var packs: String
    @State private var followGroup: Bool
    @FocusState private var field: Field?

    private enum Field: Hashable { case total, paid, free, packs }

    init(model: AppModel, id: UUID) {
        self.model = model
        self.id = id
        let item = model.activeItems.first { $0.id == id }
        let offer = item?.offer ?? Offer()
        _kind = State(initialValue: offer.kind)
        _total = State(initialValue: [.bundle, .perPack].contains(offer.kind)
                       ? L.number(offer.total, digits: 6, minimum: L.currencyDigits(model.currency)) : "")
        _paid = State(initialValue: String(offer.paid))
        _free = State(initialValue: String(offer.free))
        _packs = State(initialValue: String(item?.packs ?? 1))
        _followGroup = State(initialValue: offer.kind == .regular)
    }

    var body: some View {
        let item = model.activeItems.first { $0.id == id }
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                SheetTitle(title: L.f("offer.for", item?.name ?? ""), id: "offer.title")
                ForEach(OfferKind.allCases, id: \.self) { option in kindRow(option) }
                if kind == .bundle || kind == .perPack {
                    input("offer.total", value: $total, at: .total, decimal: true)
                        .onAppear { if followGroup { field = .total } }
                        .onChange(of: total) { _, text in
                            if field == .total, MoneyInput.priceFinished(text, currency: model.currency, locale: model.locale) {
                                field = .paid
                            }
                        }
                }
                if kind != .regular {
                    input(kind == .freePacks ? "offer.paid" : "offer.group", value: $paid, at: .paid)
                }
                if kind == .freePacks { input("offer.free", value: $free, at: .free) }
                input("offer.packs", value: $packs, at: .packs)
                preview(item)
                if kind != .regular { Text(L.t("offer.hint")).note() }
                Action(title: L.t("offer.apply"), id: "offer.apply", primary: true, fill: true) { apply() }
                    .disabled(offer == nil || integer(packs) == nil || !model.hasPro)
            }
            .padding(16)
        }
        .onChange(of: paid) { _, _ in updatePacks() }
        .onChange(of: free) { _, _ in updatePacks() }
        .background(Palette.paper)
        .presentationDragIndicator(.visible)
    }

    private func kindRow(_ option: OfferKind) -> some View {
        let on: Bool = kind == option
        let icon: String = on ? "checkmark.circle.fill" : "circle"
        let stroke: Color = on ? Palette.accent : Palette.line
        let traits: AccessibilityTraits = on ? .isSelected : []
        return Action(title: option.label, id: "offer.kind.\(option.rawValue)", icon: icon) { select(option) }
            .ticket(stroke: stroke)
            .accessibilityAddTraits(traits)
    }

    private func previewQuote(_ base: ShelfItem?) -> Quote?? {
        guard let offer, let count = integer(packs), var item = base else { return nil }
        item.offer = offer
        return .some(item.quote(locale: model.locale, packs: count))
    }

    @ViewBuilder
    private func preview(_ base: ShelfItem?) -> some View {
        if let result = previewQuote(base) {
            if let quote = result {
                Text(L.f("offer.cost", L.money(quote.cost, code: model.currency), quote.packs))
                    .font(.headline).accessibilityIdentifier("offer.preview")
                Text(model.unitPrice(quote)).note()
            } else {
                Text(L.t("offer.needsPrice")).note()
            }
        }
    }

    private func input(_ label: String, value: Binding<String>, at: Field, decimal: Bool = false) -> some View {
        let binding = Binding(
            get: { value.wrappedValue },
            set: { text in
                guard text.utf8.count <= 64 else { return }
                if at == .packs { followGroup = false }
                value.wrappedValue = text
            }
        )
        return VStack(alignment: .leading, spacing: 3) {
            Text(L.t(label)).note()
            TextField("—", text: binding)
                .font(.system(.body, design: .monospaced)).keyboardType(decimal ? .decimalPad : .numberPad)
                .focused($field, equals: at).padding(.horizontal, 9).frame(minHeight: 44).ticket()
                .accessibilityLabel(L.t(label)).accessibilityIdentifier(label)
        }
    }

    private func integer(_ text: String) -> Int? {
        guard let value = Int(text), (1...9999).contains(value) else { return nil }
        return value
    }

    private var offer: Offer? {
        switch kind {
        case .regular: return Offer()
        case .bundle, .perPack:
            guard let amount = MoneyInput.parse(total, locale: model.locale), amount >= 0,
                  let paid = integer(paid) else { return nil }
            return Offer(kind: kind, total: amount, paid: paid)
        case .freePacks:
            guard let paid = integer(paid), let free = integer(free), paid + free <= 9999 else { return nil }
            return Offer(kind: kind, paid: paid, free: free)
        }
    }

    private func select(_ value: OfferKind) {
        guard kind != value else { return }
        kind = value
        followGroup = true
        updatePacks()
        field = value == .bundle || value == .perPack ? .total : nil
    }

    private func updatePacks() {
        guard followGroup else { return }
        let group = integer(paid) ?? 2
        switch kind {
        case .regular: packs = "1"
        case .bundle: packs = String(group)
        case .perPack: packs = "1"
        case .freePacks: packs = String(group + (integer(free) ?? 1))
        }
    }

    private func apply() {
        guard model.hasPro, let offer, let count = integer(packs),
              let index = model.data.draft.items.firstIndex(where: { $0.id == id }) else { return }
        var item = model.data.draft.items[index]
        item.offer = offer
        item.packs = count
        model.data.draft.items[index] = item
        dismiss()
    }
}
