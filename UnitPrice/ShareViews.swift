import SwiftUI
import UIKit

struct SharePayload: Identifiable {
    let id = UUID()
    var items: [Any]
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareAcknowledgement: View {
    var body: some View {
        Text(L.t("share.ready")).note().accessibilityIdentifier("share.requested")
    }
}

enum ShareFiles {
    static func write(_ data: Data, filename: String) throws -> URL {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("UnitPriceShares", isDirectory: true)
        let now = Date()
        if let old = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) {
            for url in old {
                if let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   now.timeIntervalSince(created) > 86_400 {
                    try? manager.removeItem(at: url)
                }
            }
        }
        let container = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: container, withIntermediateDirectories: true)
        let url = container.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}

struct SavingsCardData {
    let heading: String
    let amount: String
    let detail: String
    var extra: String?
}

@MainActor
struct SavingsSheet: View {
    @ObservedObject var model: AppModel
    let milestone: Bool
    var alternativeID: UUID? = nil
    @State private var extra = ""
    @State private var includeExtra = false
    @State private var includeDate = false
    @State private var useEstimate = false
    @State private var qr: CGImage?
    @State private var requested = false
    @State private var sharing = false
    @State private var exported: SharePayload?
    @State private var message: String?

    private var currency: String { milestone ? "USD" : model.currency }
    private var daily: Decimal { model.data.total(currency: currency, day: DayKey.local(model.currentTime)) }

    private var estimate: Decimal? {
        let comparison = model.comparison
        guard let chosen = comparison.lowest,
              let other = comparison.alternative(preferredID: alternativeID) else { return nil }
        return Comparison.savings(chosen: chosen, alternative: other)
    }

    private var card: SavingsCardData {
        let key: String
        let amount: Decimal
        let detail: String
        if milestone {
            key = "share.milestoneHeading"
            amount = model.data.total(currency: "USD")
            detail = L.t("share.milestoneDetail")
        } else if daily > 0 && !useEstimate {
            key = "share.savedHeading"
            amount = daily
            detail = L.t("share.dayDetail")
        } else if let estimate, estimate > 0 {
            key = "share.couldHeading"
            amount = estimate
            detail = L.t("share.estimateDetail")
        } else {
            key = "share.difference"
            amount = 0
            detail = L.t("share.estimateDetail")
        }

        var parts: [String] = []
        if includeExtra, !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(extra) }
        if includeDate { parts.append(model.currentTime.formatted(date: .abbreviated, time: .omitted)) }
        return SavingsCardData(heading: L.t(key), amount: L.money(amount, code: currency), detail: detail,
                               extra: parts.isEmpty ? nil : parts.joined(separator: " · "))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                SheetTitle(title: L.t(milestone ? "milestone.title" : "share.title"), id: "share.title")
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / 360, 0.82)
                    SavingsCard(card: card, qr: qr)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: 360 * scale, height: 450 * scale, alignment: .topLeading)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("share.preview")
                }.frame(height: 369)
                HStack(spacing: 4) {
                    Action(title: L.t("share.image"), id: "share.image", icon: "square.and.arrow.up", primary: true, fill: true) {
                        makeShare()
                    }.disabled(sharing || qr == nil)
                    Action(title: L.t("share.copy"), id: "share.copy") {
                        if !Launch.uiTesting { UIPasteboard.general.string = L.t("share.caption") }
                        message = L.t("share.copied")
                    }
                }
                if requested { ShareAcknowledgement() }
                if let message { Text(message).note() }
                if !milestone && daily > 0 && (estimate ?? 0) > 0 {
                    Toggle(L.t("share.useEstimate"), isOn: $useEstimate).accessibilityIdentifier("share.estimate")
                }
                Toggle(L.t("share.includeDate"), isOn: $includeDate).accessibilityIdentifier("share.includeDate")
                Toggle(L.t("share.includeExtra"), isOn: $includeExtra).accessibilityIdentifier("share.includeExtra")
                if includeExtra {
                    TextField(L.t("share.extra"), text: $extra)
                        .padding(9).frame(minHeight: 44).ticket().accessibilityIdentifier("share.extra")
                        .onChange(of: extra) { _, value in if value.count > 56 { extra = String(value.prefix(56)) } }
                }
            }.padding(14)
        }
        .background(Palette.paper)
        .sheet(item: $exported) { payload in ActivitySheet(items: payload.items) }
        .task {
            let target = DownloadQR.target(appStoreID: Bundle.main.infoDictionary?["APP_STORE_ID"] as? String)
            qr = await Task.detached(priority: .utility) { DownloadQR.image(for: target) }.value
            if qr == nil { message = L.t("share.error") }
            if milestone { model.data.milestonesSeen.insert("USD") }
        }
    }

    private func makeShare() {
        requested = false
        message = nil
        sharing = true
        let renderer = ImageRenderer(content: SavingsCard(card: card, qr: qr).environment(\.colorScheme, .light))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let data = renderer.uiImage?.pngData() else {
            message = L.t("share.error")
            sharing = false
            return
        }
        Task {
            defer { sharing = false }
            do {
                let url = try await Task.detached(priority: .utility) {
                    try ShareFiles.write(data, filename: "UnitPrice.png")
                }.value
                if Launch.uiTesting { requested = true }
                else { exported = SharePayload(items: [url, L.t("share.caption")]) }
            } catch {
                message = L.t("share.error")
            }
        }
    }
}

private struct SavingsCard: View {
    let card: SavingsCardData
    let qr: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(L.t("home.title")).font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "tag").accessibilityHidden(true)
            }.foregroundStyle(Palette.muted)
            Rectangle().fill(Palette.line).frame(height: 1)
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 27, height: 4)
            Text(card.heading).font(.system(size: 26, weight: .medium, design: .serif)).lineLimit(2)
            Text(card.amount).font(.system(size: 66, weight: .medium, design: .serif))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.45)
            Text(card.detail).font(.system(size: 14)).foregroundStyle(Palette.muted)
            if let extra = card.extra {
                Text(extra).font(.system(size: 12)).lineLimit(2).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("share.tags")).font(.system(size: 12, weight: .semibold))
                    Text(L.t("share.scan")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                if let qr {
                    Image(decorative: qr, scale: 1).interpolation(.none).resizable()
                        .frame(width: 72, height: 72)
                        .padding(8).background(.white)
                        .accessibilityHidden(true)
                } else {
                    Color.white.frame(width: 88, height: 88)
                }
            }
        }
        .padding(23)
        .frame(width: 360, height: 450, alignment: .leading)
        .background(Palette.card)
        .foregroundStyle(Palette.ink)
        .environment(\.dynamicTypeSize, .medium)
    }
}
