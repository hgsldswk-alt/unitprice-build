import SwiftUI

@MainActor
struct CompareView: View {
    @ObservedObject var model: AppModel
    @Binding var sheet: AppSheet?
    @Binding var editing: Bool
    @Binding var resumeEntry: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: Field?
    @State private var autoPrice: UUID?
    @State private var resumeField: Field?
    @State private var removed: (ShelfItem, Int)?
    @State private var scrollingTo: UUID?
    @State private var alternativeID: UUID?

    private enum Field: Hashable {
        case price(UUID), size(UUID), sheets(UUID)
        var id: UUID {
            switch self {
            case .price(let id), .size(let id), .sheets(let id): id
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        trialNotice
                        cards
                        feedback
                        controls
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .scrollDismissesKeyboard(.never)
                .onChange(of: scrollingTo) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .top) }
                    scrollingTo = nil
                }
            }
            if let focused { keyboardBar(focused) }
        }
        .task(id: model.ready) {
            guard model.ready, model.activeItems.allSatisfy(\.isEmpty), sheet == nil,
                  let first = model.activeItems.first else { return }
            if Launch.testFlag("-paywall") { return }
            do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            guard sheet == nil, focused == nil else { return }
            focused = .price(first.id)
        }
        .onDisappear { editing = false }
        .onChange(of: focused) { _, value in
            editing = value != nil
            if case .price(let id) = value, model.activeItems.first(where: { $0.id == id })?.price.isEmpty == true {
                autoPrice = id
            } else {
                autoPrice = nil
            }
            if value == nil { model.recordReviewUse() }
        }
        .onChange(of: model.comparison.ready) { _, ready in if ready { model.recordReviewUse() } }
        .onChange(of: model.hasPro) { _, hasPro in
            if !hasPro, let focused, !model.activeItems.contains(where: { $0.id == focused.id }) { self.focused = nil }
        }
        .onChange(of: sheet?.id) { _, id in
            if id == nil, let resumeField {
                self.resumeField = nil
                focused = resumeField
            }
        }
        .onChange(of: resumeEntry) { _, resume in
            guard resume else { return }
            defer { resumeEntry = false }
            if let resumeField {
                let item = model.activeItems.first { $0.id == resumeField.id }
                self.resumeField = item?.paperPly != nil ? .size(resumeField.id) : resumeField
            } else if let first = model.activeItems.first {
                focused = .price(first.id)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L.t("home.title")).font(.title.bold()).accessibilityAddTraits(.isHeader)
                Text(L.t("home.caption")).note()
            }
            Spacer(minLength: 4)
            Action(title: L.t("clear"), id: "compare.clear") {
                model.clear()
                removed = nil
                alternativeID = nil
                focused = model.activeItems.first.map { .price($0.id) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 7)
    }

    @ViewBuilder private var trialNotice: some View {
        if !Launch.isFree, !model.hasPurchased, model.hasPro {
            Action(title: L.f("trial.notice", model.entitlement.daysLeft(at: model.now)),
                   id: "compare.trial", fill: true) {
                present(.paywall)
            }
            .ticket()
        }
    }

    @ViewBuilder private var cards: some View {
        let items = model.activeItems
        let basis = model.comparison
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            ForEach(Array(items.prefix(2))) { item in card(item, comparison: basis).id(item.id) }
        }
        ForEach(Array(items.dropFirst(2))) { item in card(item, comparison: basis).id(item.id) }
    }

    private func card(_ item: ShelfItem, comparison: Comparison) -> some View {
        let quote = model.quotes.first { $0.id == item.id }
        let winner = quote.map { comparison.isWinner($0) } ?? false
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 1) {
                Text(item.name).font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if model.hasPro, model.activeItems.count > 2 {
                    Button {
                        remove(item.id)
                    } label: {
                        Image(systemName: "minus.circle")
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.f("compare.remove", item.name))
                    .accessibilityIdentifier("compare.remove.\(item.letter)")
                }
            }
            field(item, key: \.price, label: L.t("field.price"), suffix: model.currency, focus: .price(item.id), id: "price")
            field(item, key: \.size, label: L.t(item.paperPly == nil ? "field.size" : "field.rolls"),
                  focus: .size(item.id), id: "size")
            if item.paperPly != nil && item.unit != .rolls {
                field(item, key: \.sheetsPerRoll, label: L.t("field.sheets"), focus: .sheets(item.id), id: "sheets")
            }

            HStack(spacing: 0) {
                Action(title: item.unit.label, id: "compare.unit.\(item.letter)", icon: "chevron.down") {
                    resumeField = focused ?? .size(item.id)
                    present(.unit(item.id))
                }
                .accessibilityLabel(L.f("compare.unitFor", item.name, item.unit.label))
                Spacer(minLength: 0)
                Action(title: L.t("offer.title"), id: "compare.offer.\(item.letter)",
                       icon: item.offer.kind == .regular ? nil : "checkmark") {
                    present(model.hasPro ? .offer(item.id) : .paywall)
                }
                .accessibilityLabel(L.f("compare.offerFor", item.name))
            }

            if let quote {
                Text(model.unitPrice(quote)).font(.system(.headline, design: .monospaced))
                    .minimumScaleFactor(0.65).accessibilityIdentifier("compare.rate.\(item.letter)")
                if item.packs > 1 || (model.hasPro && item.offer.kind != .regular) {
                    Text(L.f("offer.cost", L.money(quote.cost, code: model.currency), quote.packs)).note()
                }
                if comparison.ready {
                    relative(quote, comparison: comparison, winner: winner)
                }
            } else if let issue = inputError(item) {
                Text(issue).note().accessibilityIdentifier("compare.issue.\(item.letter)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .ticket(fill: winner ? Palette.highlight : Palette.card, stroke: winner ? Palette.accent : Palette.line)
    }

    private func field(_ item: ShelfItem, key: WritableKeyPath<ShelfItem, String>, label: String,
                       suffix: String? = nil, focus: Field, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
            HStack(spacing: 2) {
                TextField("—", text: Binding(
                    get: { model.data.draft.items.first(where: { $0.id == item.id })?[keyPath: key] ?? "" },
                    set: { text in
                        guard text.utf8.count <= 64,
                              let index = model.data.draft.items.firstIndex(where: { $0.id == item.id }) else { return }
                        model.data.draft.items[index][keyPath: key] = text
                        if id == "price", autoPrice == item.id, focused == focus,
                           MoneyInput.priceFinished(text, currency: model.currency, locale: model.locale) {
                            focused = .size(item.id)
                        }
                    }
                ))
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .keyboardType(.decimalPad)
                .focused($focused, equals: focus)
                .accessibilityLabel(L.f("field.for", item.name, label))
                .accessibilityIdentifier("compare.\(id).\(item.letter)")
                .submitLabel(.next)
                .onSubmit { advance(focus) }
                if let suffix { Text(suffix).font(.caption2).foregroundStyle(Palette.muted).accessibilityHidden(true) }
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 44)
            .ticket(fill: .white, stroke: focused == focus ? Palette.accent : Palette.line, radius: 8)
        }
    }

    private func inputError(_ item: ShelfItem) -> String? {
        if !item.price.isEmpty, !(MoneyInput.parse(item.price, locale: model.locale).map { $0 >= 0 } ?? false) {
            return L.t("error.price")
        }
        if !item.size.isEmpty, !(MoneyInput.parse(item.size, locale: model.locale).map { $0 > 0 } ?? false) {
            return L.t("error.size")
        }
        if item.paperPly != nil, !item.sheetsPerRoll.isEmpty,
           !(MoneyInput.parse(item.sheetsPerRoll, locale: model.locale).map { $0 > 0 } ?? false) {
            return L.t("error.sheets")
        }
        return nil
    }

    private func relative(_ quote: Quote, comparison: Comparison, winner: Bool) -> some View {
        let caption: String
        if winner {
            caption = L.t(comparison.tie ? "result.tie" : "result.winner")
        } else if let percent = comparison.higherPercent(quote) {
            caption = percent < Decimal(string: "0.1")! ? L.t("result.near") : L.f("result.higher", L.number(percent, digits: 1))
        } else if let lowest = comparison.lowest {
            let diff = (quote.rate - lowest.rate) * model.display(for: quote.unit).factor
            caption = L.f("result.absolute", L.money(diff, code: model.currency, precision: 3))
        } else {
            caption = ""
        }
        return Text(caption).font(.caption.weight(.semibold))
            .foregroundStyle(winner ? Palette.onAccent : Palette.muted)
            .accessibilityIdentifier("compare.relative.\(quote.id)")
    }

    @ViewBuilder private var feedback: some View {
        if model.comparison.mismatch {
            Text(L.t("error.mismatch")).note().frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).ticket().accessibilityIdentifier("compare.mismatch")
        }
        if let chosen = model.comparison.lowest {
            result(chosen)
        }
    }

    private func result(_ chosen: Quote) -> some View {
        let comparison = model.comparison
        let display = model.display(for: chosen.unit)
        let alternatives = comparison.alternatives
        let alternative = comparison.alternative(preferredID: alternativeID)
        let saved = alternative.map { Comparison.savings(chosen: chosen, alternative: $0) } ?? 0
        let purchase = model.data.purchases.first { $0.id == model.data.draft.id }
        let currentName = model.activeItems.first(where: { $0.id == chosen.id })?.name ?? ""
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(comparison.tie ? L.t("result.tie") : L.f("result.best", currentName))
                    .font(.headline).accessibilityIdentifier("compare.result")
                Spacer(minLength: 4)
                Menu {
                    ForEach(DisplayUnit.allCases.filter { $0.unit.dimension == chosen.unit.dimension }, id: \.self) { unit in
                        Button(unit.label) { model.data.draft.display = unit }
                            .accessibilityIdentifier("display.\(unit.rawValue)")
                    }
                } label: {
                    Label(display.label, systemImage: "chevron.down").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 6).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(L.t("display.title"))
                .accessibilityIdentifier("compare.displayUnit")
            }

            if let alternative,
               let percent = Comparison.lowerPercent(chosen: chosen, alternative: alternative),
               let name = model.activeItems.first(where: { $0.id == alternative.id })?.name {
                let label = percent < Decimal(string: "0.1")!
                    ? L.f("result.lowerNear", name)
                    : L.f("result.lower", L.number(percent, digits: 1), name)
                Text(label).note().accessibilityIdentifier("compare.lower")
            }

            if comparison.ranked.count > 2, focused == nil {
                rankings(comparison)
            }

            if let purchase {
                Text(L.f("share.saved", L.money(purchase.saved, code: purchase.currency))).font(.subheadline.bold())
                    .accessibilityIdentifier("compare.logged")
                Action(title: L.t("undo"), id: "compare.undoPurchase") {
                    model.data.purchases.removeAll { $0.id == purchase.id }
                }
            } else if let alternative, saved > 0 {
                Text(L.f("share.could", L.money(saved, code: model.currency))).font(.subheadline.bold())
                    .accessibilityIdentifier("compare.savings")
                let name = model.activeItems.first { $0.id == alternative.id }?.name ?? ""
                Text(L.f("result.baseline", L.number(chosen.quantity / chosen.unit.factor), chosen.unit.label, name)).note()
                if alternatives.count > 1 {
                    Menu {
                        ForEach(alternatives) { quote in
                            Button(model.activeItems.first { $0.id == quote.id }?.name ?? "") { alternativeID = quote.id }
                                .accessibilityIdentifier("compare.baseline.\(quote.id)")
                        }
                    } label: {
                        Text(L.t("result.changeBaseline")).font(.footnote)
                            .padding(.horizontal, 7).frame(minWidth: 44, minHeight: 44)
                    }.accessibilityIdentifier("compare.baseline")
                }
                Action(title: L.f("purchase.log", chosen.packs), id: "compare.log") {
                    model.logPurchase(chosen: chosen, alternative: alternative)
                }
            }
            if focused == nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 1) { resultActions }
                    VStack(alignment: .leading, spacing: 0) { resultActions }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .ticket()
    }

    @ViewBuilder private var resultActions: some View {
        Action(title: L.t("save.price"), id: "compare.save", icon: "bookmark") {
            present(model.hasPro ? .save : .paywall)
        }
        Action(title: L.t("share.title"), id: "compare.share", icon: "square.and.arrow.up") {
            present(.share(alternativeID: alternativeID))
        }
        if model.currency == "USD", model.data.total(currency: "USD") >= LocalData.milestone,
           !model.data.milestonesSeen.contains("USD") {
            Action(title: L.t("milestone.view"), id: "compare.milestone") { present(.milestone) }
        }
    }

    private func rankings(_ comparison: Comparison) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.t("result.ranking")).font(.subheadline.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("compare.ranking")
            ForEach(comparison.ranked) { quote in
                if let item = model.activeItems.first(where: { $0.id == quote.id }) {
                    Action(title: L.f("result.rankRow", item.name, model.unitPrice(quote)),
                           id: "compare.rank.\(item.letter)", fill: true) {
                        focused = .price(item.id)
                        scrollingTo = item.id
                    }
                    .ticket(fill: comparison.isWinner(quote) ? Palette.highlight : Palette.card)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 5) {
            if model.activeItems.count < 10 {
                Action(title: L.t("compare.add"), id: "compare.add", icon: "plus", primary: true) {
                    guard model.hasPro else { present(.paywall); return }
                    if let id = model.addItem() { focused = .price(id); scrollingTo = id }
                }
            }
            if removed != nil {
                Action(title: L.t("undo"), id: "compare.undoItem") {
                    if let (item, index) = removed, model.hasPro, model.data.draft.items.count < 10,
                       !model.data.draft.items.contains(where: { $0.letter == item.letter }) {
                        model.data.draft.items.insert(item, at: min(index, model.data.draft.items.count))
                    }
                    removed = nil
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func keyboardBar(_ field: Field) -> some View {
        let name = model.activeItems.first { $0.id == field.id }?.name ?? ""
        let next = successor(field)
        return HStack(spacing: 2) {
            Text(name).note()
            Spacer(minLength: 0)
            if let next {
                Action(title: L.t(next.id == field.id ? "keyboard.field" : "keyboard.next"),
                       id: next.id == field.id ? "keyboard.field" : "keyboard.next") { advance(field) }
            }
            Action(title: L.t("keyboard.done"), id: "keyboard.done", primary: true) { focused = nil }
        }
        .padding(.horizontal, 10)
        .background(Palette.paper)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1).allowsHitTesting(false) }
    }

    private func successor(_ field: Field) -> Field? {
        let items = model.activeItems
        guard let index = items.firstIndex(where: { $0.id == field.id }) else { return nil }
        switch field {
        case .price: return .size(field.id)
        case .size where items[index].paperPly != nil && items[index].unit != .rolls: return .sheets(field.id)
        default: return items.indices.contains(index + 1) ? .price(items[index + 1].id) : nil
        }
    }

    private func advance(_ field: Field) {
        let next = successor(field)
        focused = next
        if let next, model.activeItems.dropFirst(2).contains(where: { $0.id == next.id }) { scrollingTo = next.id }
    }

    private func present(_ target: AppSheet) {
        focused = nil
        sheet = target
    }

    private func remove(_ id: UUID) {
        guard model.hasPro, model.data.draft.items.count > 2,
              let index = model.data.draft.items.firstIndex(where: { $0.id == id }) else { return }
        if focused?.id == id { focused = nil }
        let old = model.data.draft.items.remove(at: index)
        removed = (old, index)
    }
}
