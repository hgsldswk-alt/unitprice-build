import Foundation
import XCTest

final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private let switchTimeout: TimeInterval = 10

    private enum StoreLanguage: String, CaseIterable {
        case en, simplified = "zh-Hans", traditional = "zh-Hant"
        var locale: String {
            switch self {
            case .en: "en_US"
            case .simplified: "zh_CN"
            case .traditional: "zh_TW"
            }
        }
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 900
    }

    private func launch(_ flags: [String] = [], language: StoreLanguage = .en,
                        reset: Bool = true, environment: [String: String] = [:]) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language.rawValue))", "-AppleLocale", language.locale]
            + (reset ? ["-reset"] : []) + flags
        app.launchEnvironment = environment
        app.launch()
        if flags.contains("-paywall") {
            wait("paywall.title")
        } else if flags.contains("-demo-history") {
            wait("history.title")
        } else if flags.contains("-demo-share") {
            wait("share.title")
        } else {
            XCTAssertTrue(button("compare.clear").waitForExistence(timeout: switchTimeout))
        }
    }

    private func button(_ id: String) -> XCUIElement { app.buttons.matching(identifier: id).firstMatch }
    private func text(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func field(_ id: String) -> XCUIElement { app.textFields.matching(identifier: id).firstMatch }

    private func staple(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                         "saved.staple.", name)).firstMatch
    }

    private func tap(_ id: String) {
        let target = button(id)
        if !target.waitForExistence(timeout: 3) || !target.isHittable {
            for _ in 0..<4 {
                if target.exists && target.isHittable { break }
                app.swipeUp()
            }
        }
        XCTAssertTrue(target.exists && target.isHittable, id)
        if !target.isEnabled {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"),
                                                  object: target)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: switchTimeout), .completed, id)
        }
        target.tap()
    }

    private func type(_ value: String, on id: String, focus: Bool = true) {
        let input = field(id)
        XCTAssertTrue(input.waitForExistence(timeout: switchTimeout), id)
        if focus { input.tap() }
        input.typeText(value)
    }

    private func replace(_ id: String, with value: String) {
        let input = field(id)
        XCTAssertTrue(input.waitForExistence(timeout: switchTimeout))
        let old = input.value as? String ?? ""
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2))
        input.typeText(value)
    }

    private func wait(_ id: String) {
        XCTAssertTrue(text(id).waitForExistence(timeout: switchTimeout), id)
    }

    private func tapByPrefix(_ prefix: String) {
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: switchTimeout), prefix)
        for _ in 0..<4 where !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.isHittable, prefix)
        target.tap()
    }

    func testTwoItemsOneNextTapAndDraftResumes() {
        launch()
        XCTAssertTrue(button("keyboard.done").waitForExistence(timeout: switchTimeout))
        type("4.49", on: "compare.price.0", focus: false)
        type("18", on: "compare.size.0", focus: false)
        tap("keyboard.next")
        type("5.99", on: "compare.price.1", focus: false)
        type("32", on: "compare.size.1", focus: false)
        wait("compare.result")
        XCTAssertEqual(text("compare.result").label, "Best value · Item B")
        XCTAssertEqual(text("compare.lower").label, "25% less than Item A")
        tap("keyboard.done")
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        launch(reset: false)
        wait("compare.result")
        tap("compare.clear")
        XCTAssertTrue(button("keyboard.done").waitForExistence(timeout: switchTimeout))
        XCTAssertFalse(text("compare.result").exists)
    }

    func testUnitMismatchCorrectionAndAddingThirdItem() {
        launch(["-demo"])
        tap("compare.unit.1")
        tap("unit.choose.ml")
        wait("compare.mismatch")
        if button("keyboard.done").isHittable { tap("keyboard.done") }
        tap("compare.unit.1")
        tap("unit.choose.lb")
        replace("compare.size.1", with: "2")
        tap("keyboard.done")
        wait("compare.result")
        XCTAssertFalse(text("compare.mismatch").exists)
        tap("compare.add")
        type("7.29", on: "compare.price.2", focus: false)
        type("40", on: "compare.size.2", focus: false)
        tap("keyboard.done")
        wait("compare.result")
        wait("compare.ranking")
        tap("compare.remove.2")
        XCTAssertFalse(field("compare.price.2").exists)
        tap("compare.undoItem")
        XCTAssertTrue(button("compare.remove.2").waitForExistence(timeout: switchTimeout))
    }

    func testBundleEditAppliesAndReopenShowsCost() {
        launch(["-demo"])
        tap("compare.offer.1")
        tap("offer.kind.bundle")
        type("5.00", on: "offer.total", focus: false)
        tap("offer.apply")
        tap("compare.offer.1")
        wait("offer.preview")
        XCTAssertEqual(text("offer.preview").label, "$5.00 for 2 pack(s)")
    }

    func testSavedHistoryComparisonAndArchive() {
        launch(["-demo"])
        tap("compare.save")
        type("Rice", on: "save.name")
        tap("save.confirm")
        wait("app.notice")
        tap("notice.close")
        tap("tab.saved")
        let rice = staple(named: "Rice")
        XCTAssertTrue(rice.waitForExistence(timeout: switchTimeout))
        rice.tap()
        type("4.99", on: "history.price")
        wait("history.delta")
        tap("history.save")
        wait("history.saved")
        tap("history.pin")
        tap("history.back")
        tap("archive.export")
        wait("share.requested")
    }

    func testImportPreviewFileAndInvalidCode() {
        let json = #"{"v":1,"items":[{"name":"Olive oil","unit":"ml"}]}"#
        let base = Data(json.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let code = "UP1:" + base
        launch(["-demo"], environment: ["UNITPRICE_LIST_CODE": "UP2:invalid\n", "UNITPRICE_LIST_FILE": " \n" + code + "\n"])
        tap("tab.saved")
        tap("list.paste")
        wait("app.notice")
        XCTAssertFalse(text("import.title").exists)
        tap("notice.close")
        tap("list.importFile")
        wait("import.title")
        XCTAssertTrue(app.staticTexts["Olive oil"].exists)
        tap("import.confirm")
        wait("app.notice")
        XCTAssertTrue(staple(named: "Olive oil").exists)

        launch(environment: ["UNITPRICE_LIST_CODE": "\n" + code + "\n"])
        tap("tab.saved")
        tap("list.paste")
        wait("import.title")
        tap("import.confirm")
        XCTAssertTrue(staple(named: "Olive oil").waitForExistence(timeout: switchTimeout))
        tap("list.export")
        wait("share.requested")
    }

    func testPurchaseLogShareAndUndo() {
        launch(["-demo"])
        tap("compare.log")
        wait("compare.logged")
        XCTAssertFalse(button("compare.log").exists)
        tap("compare.share")
        wait("share.preview")
        tap("share.image")
        wait("share.requested")
        tap("sheet.close")
        tap("compare.undoPurchase")
        XCTAssertTrue(button("compare.log").waitForExistence(timeout: switchTimeout))
    }

    func testMilestoneAppearsOnCrossingAndDisappearsAfterUndo() {
        launch(["-demo", "-milestone-demo"])
        XCTAssertFalse(button("compare.milestone").exists)
        tap("compare.log")
        tap("compare.milestone")
        wait("share.preview")
        tap("share.image")
        wait("share.requested")
        tap("sheet.close")
        XCTAssertFalse(button("compare.milestone").exists)
        tap("compare.undoPurchase")
        tap("tab.saved")
        XCTAssertFalse(button("saved.milestone").exists)
    }

    func testExpiredStillCalculatesAndReadsRecords() {
        launch(["-expired", "-demo"])
        wait("compare.result")
        tap("compare.add")
        wait("paywall.title")
        XCTAssertTrue(button("paywall.buy").exists)
        XCTAssertTrue(button("paywall.restore").exists)
        tap("sheet.close")
        tap("tab.saved")
        tapByPrefix("saved.staple.")
        wait("history.title")
        XCTAssertFalse(button("history.save").exists)
        XCTAssertTrue(app.staticTexts["Price history"].exists)
        tap("history.back")
        tap("archive.export")
        wait("share.requested")
    }

    func testPurchasedStateUnlocksAfterTrialExpiry() {
        launch(["-expired", "-purchased", "-demo"])
        wait("compare.result")
        tap("compare.add")
        XCTAssertTrue(field("compare.price.2").waitForExistence(timeout: switchTimeout))
        XCTAssertFalse(text("paywall.title").exists)
    }

    func testThirdDayReviewWaitsForIdleAndRunsOnce() {
        launch(["-review-demo"])
        XCTAssertTrue(button("keyboard.done").waitForExistence(timeout: switchTimeout))
        type("4.49", on: "compare.price.0", focus: false)
        type("18", on: "compare.size.0", focus: false)
        tap("keyboard.next")
        type("5.99", on: "compare.price.1", focus: false)
        type("32", on: "compare.size.1", focus: false)
        wait("compare.result")
        XCTAssertFalse(text("review.attempted").waitForExistence(timeout: 2.5))
        tap("keyboard.done")
        wait("review.attempted")
        XCTAssertEqual(text("review.attempted").label, "1")
        launch(["-review-demo"], reset: false)
        wait("compare.result")
        XCTAssertFalse(text("review.attempted").waitForExistence(timeout: 3))
    }

    func testStoreScreenshots() {
        for language in StoreLanguage.allCases {
            launch(["-demo"], language: language)
            wait("compare.result")
            field("compare.size.1").tap()
            wait("compare.result")
            shot("store-\(language.rawValue)-01-compare")
            tap("keyboard.done")

            launch(["-demo-convert"], language: language)
            wait("compare.result")
            shot("store-\(language.rawValue)-02-convert")

            launch(["-demo-offer"], language: language)
            tap("compare.offer.1")
            wait("offer.preview")
            shot("store-\(language.rawValue)-03-offer")

            launch(["-demo-history"], language: language)
            wait("history.delta")
            shot("store-\(language.rawValue)-04-history")

            launch(["-demo"], language: language)
            tap("compare.log")
            tap("compare.share")
            wait("share.preview")
            let ready = NSPredicate(format: "exists == true AND enabled == true")
            expectation(for: ready, evaluatedWith: button("share.image"))
            waitForExpectations(timeout: switchTimeout)
            shot("store-\(language.rawValue)-05-savings")
        }
    }

    func testPaidScreenshot() {
        launch(["-paywall"], language: .simplified)
        wait("paywall.title")
        XCTAssertTrue(button("paywall.trial").exists)
        XCTAssertTrue(button("paywall.restore").exists)
        shot("paid-01-paywall")
    }

    private func shot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_SHOTS_DIR"] {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: folder.appendingPathComponent(name + ".png"))
        }
    }
}
