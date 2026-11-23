import Foundation

enum Launch {
    static let freePeriod = false
    static let arguments = ProcessInfo.processInfo.arguments

    static var uiTesting: Bool {
        #if DEBUG
        arguments.contains("-ui-testing")
        #else
        false
        #endif
    }

    static func testFlag(_ flag: String) -> Bool { uiTesting && arguments.contains(flag) }
    static var isFree: Bool { freePeriod && !["-paid-mode", "-paywall", "-expired"].contains(where: testFlag) }
    static let proID = "com.hgsldswk.unitprice.pro"
    static let trialID = "com.hgsldswk.unitprice.trial"
    static let group = "group.com.hgsldswk.unitprice"
}
