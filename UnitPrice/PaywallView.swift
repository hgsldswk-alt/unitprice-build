import StoreKit
import SwiftUI

@MainActor
struct PaywallView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                SheetTitle(title: L.t("paywall.title"), id: "paywall.title")
                Text(L.t("paywall.summary")).font(.body)
                VStack(alignment: .leading, spacing: 12) {
                    feature("compare.add", "square.stack")
                    feature("paywall.history", "clock.arrow.circlepath")
                    feature("paywall.offers", "tag")
                    feature("paywall.widget", "square.grid.2x2")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13).ticket()
                Text(model.hasPurchased ? L.t("paywall.unlocked") : L.t("paywall.trialTerms")).note()
                if !model.hasPurchased {
                    Action(title: buyLabel, id: "paywall.buy", primary: true, fill: true) {
                        Task { await model.buy(Launch.proID) }
                    }
                    .disabled(model.busy)
                    if model.hasPro || Launch.testFlag("-paywall"), model.entitlement.trialReceiptAt == nil {
                        Action(title: L.t("paywall.trial"), id: "paywall.trial", fill: true) {
                            Task { await model.buy(Launch.trialID) }
                        }
                        .disabled(model.busy)
                    }
                }
                Action(title: L.t("paywall.restore"), id: "paywall.restore", fill: true) {
                    Task { await model.restore() }
                }
                .disabled(model.busy)
                if let message = model.storeMessage { Text(message).note().accessibilityIdentifier("paywall.status") }
            }
            .padding(16)
        }
        .background(Palette.paper)
        .task { await model.loadProducts() }
    }

    private var buyLabel: String {
        if let product = model.products.first(where: { $0.id == Launch.proID }) {
            return L.f("paywall.buyPrice", product.displayPrice)
        }
        return L.t("paywall.buy")
    }

    private func feature(_ key: String, _ icon: String) -> some View {
        Label(L.t(key), systemImage: icon).font(.subheadline)
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var model: AppModel
    let openPaywall: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetTitle(title: L.t("settings.title"))
                Picker(L.t("settings.currency"), selection: Binding(get: { model.currency }, set: { newCurrency in
                    if model.data.draft.items.allSatisfy(\.isEmpty), model.data.draft.lastUnit == nil {
                        model.data.draft = .blank(currency: newCurrency, unit: newCurrency == "USD" ? .oz : .g)
                    } else {
                        model.data.draft.currency = newCurrency
                    }
                })) {
                    ForEach(AppModel.currencies, id: \.self) { code in Text(code).tag(code) }
                }
                .accessibilityIdentifier("settings.currency")
                Text(L.t("settings.currencyHint")).note()
                if !Launch.isFree {
                    Action(title: L.t("paywall.title"), id: "settings.pro", primary: true, run: openPaywall)
                }
                Text(L.t("settings.privacy")).note()
            }.padding(16)
        }
        .background(Palette.paper)
    }
}
