import StoreKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct UnitPriceApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

enum AppSheet: Identifiable {
    case unit(UUID), offer(UUID), save, share(alternativeID: UUID?), milestone, paywall, settings, imported

    var id: String {
        switch self {
        case .unit(let id): "unit-\(id)"
        case .offer(let id): "offer-\(id)"
        case .save: "save"
        case .share: "share"
        case .milestone: "milestone"
        case .paywall: "paywall"
        case .settings: "settings"
        case .imported: "import"
        }
    }
}

@MainActor
struct RootView: View {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var saved = false
    @State private var selected: UUID?
    @State private var sheet: AppSheet?
    @State private var importItems: [StapleDefinition] = []
    @State private var notice: String?
    @State private var comparisonFocus = false
    @State private var resumeEntry = false
    @State private var eventURL: URL?
    @Environment(\.requestReview) private var requestReview
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if saved {
                    if let selected, model.data.staples.contains(where: { $0.id == selected }) {
                        HistoryView(model: model, stapleID: selected, back: { self.selected = nil },
                                    pro: { sheet = .paywall }, report: { notice = $0 })
                    } else {
                        SavedView(model: model, select: { selected = $0 }, open: { sheet = $0 },
                                  processCode: previewCode, processFile: readFile, report: { notice = $0 })
                    }
                } else {
                    CompareView(model: model, sheet: $sheet, editing: $comparisonFocus, resumeEntry: $resumeEntry)
                }
            }
            .frame(maxHeight: .infinity)
            if let notice {
                HStack {
                    Text(notice).note().accessibilityIdentifier("app.notice")
                    Spacer()
                    Action(title: L.t("close"), id: "notice.close") { self.notice = nil }
                }
                .padding(.horizontal, 15)
                .background(Palette.card)
            }
            if !comparisonFocus || saved { tabs }
        }
        .disabled(!model.ready)
        .background(Palette.paper.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
        .task {
            await model.start()
            if Launch.testFlag("-paywall") { sheet = .paywall }
            if Launch.testFlag("-demo-history"), let first = model.data.staples.first {
                saved = true
                selected = first.id
            }
            if Launch.testFlag("-demo-share") { sheet = .share(alternativeID: nil) }
            if let eventURL { self.eventURL = nil; route(eventURL) }
        }
        .onReceive(timer) { _ in model.tick() }
        .onChange(of: scenePhase) { _, _ in model.tick() }
        .onChange(of: model.storageFailed) { _, failed in if failed { notice = L.t("storage.error") } }
        .onOpenURL { url in
            if model.ready { route(url) } else { eventURL = url }
        }
        .sheet(item: $sheet) { route in
            sheetContent(route)
                .foregroundStyle(Palette.ink)
                .background(Palette.paper.ignoresSafeArea())
        }
        .task(id: canRequestReview) {
            guard canRequestReview else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard canRequestReview else { return }
            model.data.review.requestedVersions.insert(appVersion)
            if Launch.uiTesting { model.reviewAttempts += 1 } else { requestReview() }
        }
        .overlay(alignment: .bottomTrailing) {
            if Launch.testFlag("-review-demo"), model.reviewAttempts > 0 {
                Text(String(model.reviewAttempts)).accessibilityIdentifier("review.attempted").padding(4)
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            Action(title: L.t("tab.compare"), id: "tab.compare", icon: "tag", fill: true) {
                saved = false; selected = nil; notice = nil
            }
            .accessibilityAddTraits(saved ? [] : .isSelected)
            Action(title: L.t("tab.saved"), id: "tab.saved", icon: "bookmark", fill: true) {
                saved = true; selected = nil; notice = nil
            }
            .accessibilityAddTraits(saved ? .isSelected : [])
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1).allowsHitTesting(false) }
    }

    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }

    private var canRequestReview: Bool {
        model.ready && !saved && !comparisonFocus && sheet == nil && notice == nil && scenePhase == .active &&
            model.comparison.ready && model.data.review.pending(version: appVersion)
    }

    @ViewBuilder private func sheetContent(_ route: AppSheet) -> some View {
        switch route {
        case .unit(let id):
            UnitSheet(model: model, id: id) { resumeEntry = true }
        case .offer(let id):
            OfferSheet(model: model, id: id)
        case .save:
            SavePriceSheet(model: model, report: { notice = $0 })
        case .share(let alternativeID):
            SavingsSheet(model: model, milestone: false, alternativeID: alternativeID)
        case .milestone:
            SavingsSheet(model: model, milestone: true)
        case .paywall:
            PaywallView(model: model)
        case .settings:
            SettingsView(model: model) {
                sheet = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    if sheet == nil { sheet = .paywall }
                }
            }
        case .imported:
            ListPreview(model: model, items: importItems, report: { notice = $0 })
        }
    }

    private func route(_ url: URL) {
        if url.isFileURL {
            readFile(url)
        } else if url.scheme == "unitprice" {
            sheet = nil
            if url.host == "staple", model.hasPro, let id = UUID(uuidString: url.lastPathComponent),
               model.data.staples.contains(where: { $0.id == id }) {
                saved = true; selected = id
            } else {
                saved = false; selected = nil; resumeEntry = true
            }
        }
    }

    private func previewCode(_ code: String) {
        saved = true
        selected = nil
        guard let items = ListCode.decode(code) else {
            notice = L.t("import.invalid")
            return
        }
        notice = nil
        importItems = items
        sheet = .imported
    }

    private func readFile(_ url: URL) {
        saved = true
        selected = nil
        Task {
            let code = await Task.detached(priority: .utility) {
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
                defer { try? handle.close() }
                guard let data = try? handle.read(upToCount: ListCode.maxBytes + 1) else { return "" }
                return String(data: data, encoding: .utf8) ?? ""
            }.value
            previewCode(code)
        }
    }
}
