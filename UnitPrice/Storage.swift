import Foundation
import Security

final class Storage: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.hgsldswk.unitprice.storage", qos: .utility)
    private let testing: Bool
    private let url: URL
    private let account = "entitlement-v1"

    struct Loaded: Sendable {
        var data: LocalData
        var entitlement: Entitlement
        var dataReadable: Bool
        var hadError: Bool
    }

    init(testing: Bool) {
        self.testing = testing
        let folder = URL.applicationSupportDirectory.appendingPathComponent("UnitPrice", isDirectory: true)
        url = folder.appendingPathComponent(testing ? "UITests-v1.json" : "Local-v1.json")
    }

    func load(defaults: LocalData, now: Date, reset: Bool) async -> Loaded {
        await withCheckedContinuation { continuation in
            queue.async {
                var hadError = false
                var dataReadable = true
                var data = defaults
                do {
                    if self.testing && reset && FileManager.default.fileExists(atPath: self.url.path) {
                        try FileManager.default.removeItem(at: self.url)
                    }
                    if FileManager.default.fileExists(atPath: self.url.path) {
                        let decoded = try JSONDecoder().decode(LocalData.self, from: Data(contentsOf: self.url))
                        guard decoded.version == 1, (2...10).contains(decoded.draft.items.count) else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        data = decoded
                    }
                } catch {
                    hadError = true
                    dataReadable = false
                }

                var entitlement = Entitlement(firstOpen: now)
                if !self.testing {
                    do {
                        entitlement = try self.readEntitlement() ?? entitlement
                        if !Launch.freePeriod, entitlement.proStartedAt == nil {
                            entitlement.proStartedAt = now
                        }
                        entitlement.observe(now)
                        try self.saveEntitlement(entitlement)
                    } catch {
                        hadError = true
                    }
                }
                continuation.resume(returning: Loaded(data: data, entitlement: entitlement,
                                                       dataReadable: dataReadable, hadError: hadError))
            }
        }
    }

    func save(_ data: LocalData, onError: @escaping @Sendable () -> Void) {
        queue.async {
            do {
                try FileManager.default.createDirectory(at: self.url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try JSONEncoder().encode(data).write(to: self.url, options: .atomic)
            } catch {
                onError()
            }
        }
    }

    func updateEntitlement(_ entitlement: Entitlement, onError: @escaping @Sendable () -> Void) {
        guard !testing else { return }
        queue.async {
            do { try self.saveEntitlement(entitlement) }
            catch { onError() }
        }
    }

    func updateWidget(_ snapshot: WidgetSnapshot, completion: @escaping @Sendable () -> Void) {
        guard !testing else { return }
        queue.async {
            guard let defaults = UserDefaults(suiteName: Launch.group),
                  let data = try? JSONEncoder().encode(snapshot) else { return }
            defaults.set(data, forKey: WidgetSnapshot.key)
            completion()
        }
    }

    private var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Launch.proID,
            kSecAttrAccount as String: account
        ]
    }

    private func readEntitlement() throws -> Entitlement? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return try JSONDecoder().decode(Entitlement.self, from: data)
    }

    private func saveEntitlement(_ entitlement: Entitlement) throws {
        let data = try JSONEncoder().encode(entitlement)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(keychainQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var query = keychainQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
