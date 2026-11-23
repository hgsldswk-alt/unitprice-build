import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SavedView: View {
    @ObservedObject var model: AppModel
    let select: (UUID) -> Void
    let open: (AppSheet) -> Void
    let processCode: (String) -> Void
    let processFile: (URL) -> Void
    let report: (String) -> Void
    @State private var importing = false
    @State private var purchase: PurchaseLog?
    @State private var exported: SharePayload?
    @State private var shareRequested = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.t("saved.title")).font(.title.bold()).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 5)
                Action(title: L.t("settings.title"), id: "saved.settings", icon: "gearshape") { open(.settings) }
            }.padding(.horizontal, 15)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    list
                    sharing
                    purchases
                }
                .padding(15)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [ListFile.type]) { result in
            switch result {
            case .success(let url): processFile(url)
            case .failure: report(L.t("import.invalid"))
            }
        }
        .sheet(item: $purchase) { purchase in
            PurchaseEditor(model: model, purchase: purchase)
        }
        .sheet(item: $exported) { payload in ActivitySheet(items: payload.items) }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L.t("saved.staples")).font(.headline)
                Spacer()
                if !model.hasPro {
                    Action(title: L.t("paywall.buy"), id: "saved.pro") { open(.paywall) }
                }
            }
            if model.data.staples.isEmpty { Text(L.t("saved.empty")).note() }
            ForEach(model.data.staples) { staple in
                Button { select(staple.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(staple.definition.name).font(.body.weight(.semibold))
                            if model.hasPro, let low = staple.lowest(currency: model.currency) {
                                Text(model.unitPrice(low.quote, display: low.display, currency: low.currency)).note()
                            } else {
                                Text(staple.definition.unit.label).note()
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                    }
                    .padding(8).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .ticket()
                .accessibilityIdentifier("saved.staple.\(staple.id)")
            }
        }
    }

    private var sharing: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L.t("saved.listActions")).font(.headline)
            Action(title: L.t("list.copy"), id: "list.copy", icon: "doc.on.doc") {
                guard let code = ListCode.encode(model.data.staples.map(\.definition)) else {
                    report(L.t("import.invalid")); return
                }
                if !Launch.uiTesting { UIPasteboard.general.string = code }
                report(L.t("list.copied"))
            }
            Action(title: L.t("list.paste"), id: "list.paste", icon: "clipboard") {
                let text = Launch.uiTesting ? ProcessInfo.processInfo.environment["UNITPRICE_LIST_CODE"] : UIPasteboard.general.string
                processCode(text ?? "")
            }
            Action(title: L.t("list.file"), id: "list.importFile", icon: "square.and.arrow.down") {
                if Launch.uiTesting, let path = ProcessInfo.processInfo.environment["UNITPRICE_LIST_PATH"] {
                    processFile(URL(fileURLWithPath: path))
                } else {
                    importing = true
                }
            }
            Action(title: L.t("list.export"), id: "list.export", icon: "square.and.arrow.up") {
                guard let code = ListCode.encode(model.data.staples.map(\.definition)) else {
                    report(L.t("import.invalid")); return
                }
                export(name: "UnitPrice.\(ListCode.fileExtension)") { Data(code.utf8) }
            }
            Action(title: L.t("archive.export"), id: "archive.export", icon: "tray.and.arrow.up") {
                let snapshot = model.data
                export(name: "UnitPrice.json") {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    return try encoder.encode(snapshot)
                }
            }
            if shareRequested { ShareAcknowledgement() }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).ticket()
    }

    private var purchases: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("purchase.title")).font(.headline)
            if model.data.purchases.isEmpty { Text(L.t("purchase.empty")).note() }
            ForEach(Set(model.data.purchases.map(\.currency)).sorted(), id: \.self) { currency in
                let today = model.data.total(currency: currency, day: DayKey.local(model.currentTime))
                let total = model.data.total(currency: currency)
                HStack {
                    Text(L.f("purchase.today", L.money(today, code: currency))).note()
                    Spacer()
                    Text(L.f("purchase.total", L.money(total, code: currency))).note()
                }
            }
            if model.data.total(currency: "USD") >= LocalData.milestone {
                Action(title: L.t("milestone.view"), id: "saved.milestone") { open(.milestone) }
            }
            ForEach(model.data.purchases.reversed()) { row in
                Button { purchase = row } label: {
                    HStack {
                        Text(row.date, style: .date)
                        Spacer()
                        Text(L.money(row.saved, code: row.currency)).monospacedDigit()
                    }.padding(9).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).ticket()
                .accessibilityIdentifier("purchase.row.\(row.id)")
            }
        }
    }

    private func export(name: String, make: @escaping @Sendable () throws -> Data) {
        shareRequested = false
        Task {
            do {
                let url = try await Task.detached(priority: .utility) {
                    try ShareFiles.write(make(), filename: name)
                }.value
                if Launch.uiTesting { shareRequested = true }
                else { exported = SharePayload(items: [url]) }
            } catch {
                report(L.t("share.error"))
            }
        }
    }
}

enum ListFile {
    static let type = UTType(exportedAs: "com.hgsldswk.unitprice.list", conformingTo: .plainText)
}

@MainActor
struct ListPreview: View {
    @ObservedObject var model: AppModel
    let items: [StapleDefinition]
    let report: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let existing = Set(model.data.staples.map(\.definition.key))
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                SheetTitle(title: L.t("import.title"), id: "import.title")
                if items.isEmpty { Text(L.t("import.empty")).note() }
                ForEach(items, id: \.key) { row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.name).font(.body.weight(.semibold))
                            Text(row.unit.label).note()
                        }
                        Spacer()
                        Text(L.t(existing.contains(row.key) ? "import.existing" : "import.new")).note()
                    }.padding(9).ticket()
                }
                Action(title: L.t("import.confirm"), id: "import.confirm", primary: true, fill: true) {
                    let success = model.importList(items)
                    report(L.t(success ? "import.done" : "import.full"))
                    dismiss()
                }
            }.padding(16)
        }
        .background(Palette.paper)
    }
}

@MainActor
struct PurchaseEditor: View {
    @ObservedObject var model: AppModel
    let purchase: PurchaseLog
    @State private var count: String
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, purchase: PurchaseLog) {
        self.model = model
        self.purchase = purchase
        _count = State(initialValue: String(purchase.actual.packs))
    }

    private var revised: PurchaseLog? {
        var revised = purchase
        guard let count = Int(count), revised.resize(to: count, locale: model.locale) else { return nil }
        return revised
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetTitle(title: L.t("purchase.edit"))
            Text(L.t("offer.packs")).note()
            TextField(L.t("offer.packs"), text: $count)
                .keyboardType(.numberPad).padding(9).frame(minHeight: 44).ticket()
                .accessibilityIdentifier("purchase.count")
            Text(L.f("purchase.baseline", model.unitPrice(purchase.baseline, display: purchase.display, currency: purchase.currency))).note()
            if let revised {
                Text(L.money(revised.saved, code: revised.currency)).font(.headline.monospacedDigit())
            }
            Action(title: L.t("save"), id: "purchase.save", primary: true, fill: true) {
                if let revised, let index = model.data.purchases.firstIndex(where: { $0.id == purchase.id }) {
                    model.data.purchases[index] = revised
                }
                dismiss()
            }.disabled(revised == nil)
            Action(title: L.t("undo"), id: "purchase.remove", fill: true) {
                model.data.purchases.removeAll { $0.id == purchase.id }
                dismiss()
            }
            Spacer()
        }
        .padding(16).background(Palette.paper.ignoresSafeArea())
    }
}
