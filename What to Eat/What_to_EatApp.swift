import SwiftData
import SwiftUI

@main
struct What_to_EatApp: App {
    @StateObject private var appContainer = AppContainer()

    private var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MealEntry.self,
            DailySummary.self,
            MedicalRecordEntry.self,
            UserPreferencesStore.self
        ])

        let storeURL = persistentStoreURL()
        let configuration = ModelConfiguration(
            "default",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Recover once from known migration failures by rotating the old store.
            if shouldResetPersistentStore(after: error) {
                rotatePersistentStore(at: storeURL)
                do {
                    return try ModelContainer(for: schema, configurations: [configuration])
                } catch {
                    fatalError("Failed to recreate ModelContainer after store reset: \(error)")
                }
            }

            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appContainer)
        }
        .modelContainer(sharedModelContainer)
    }
}

private func persistentStoreURL() -> URL {
    let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    return baseURL.appendingPathComponent("default.store")
}

private func shouldResetPersistentStore(after error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == NSCocoaErrorDomain else { return false }

    // Typical Core Data migration/load failure codes from SwiftData container setup.
    let resetCodes: Set<Int> = [134100, 134110, 134130, 134140]
    if resetCodes.contains(nsError.code) {
        return true
    }

    let message = (nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String)?.lowercased() ?? ""
    return message.contains("migration")
}

private func rotatePersistentStore(at storeURL: URL) {
    let fileManager = FileManager.default
    let suffixes = ["", "-shm", "-wal"]
    let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")

    for suffix in suffixes {
        let sourceURL = URL(fileURLWithPath: storeURL.path + suffix)
        guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

        let backupURL = sourceURL.deletingLastPathComponent().appendingPathComponent(
            sourceURL.lastPathComponent + ".backup-\(stamp)"
        )

        do {
            try fileManager.moveItem(at: sourceURL, to: backupURL)
        } catch {
            // If rotation fails, best effort delete so container creation can proceed.
            try? fileManager.removeItem(at: sourceURL)
        }
    }
}
