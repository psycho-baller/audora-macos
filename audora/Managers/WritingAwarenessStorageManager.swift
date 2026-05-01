import Foundation

final class WritingAwarenessStorageManager {
    static let shared = WritingAwarenessStorageManager()

    private let fileManager: FileManager
    private let rootDirectory: URL
    private let legacyRootDirectory: URL
    private let stateURL: URL
    private let seedURL: URL
    private let memoDirectory: URL

    private convenience init() {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.init(
            fileManager: fileManager,
            rootDirectory: applicationSupportDirectory
                .appendingPathComponent("Audora", isDirectory: true)
                .appendingPathComponent("WritingAwareness", isDirectory: true),
            legacyRootDirectory: documentsDirectory.appendingPathComponent("WritingAwareness", isDirectory: true),
            migrateLegacyStorage: true
        )
    }

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL,
        legacyRootDirectory: URL? = nil,
        migrateLegacyStorage: Bool = false
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory
        self.legacyRootDirectory = legacyRootDirectory
            ?? rootDirectory.deletingLastPathComponent().appendingPathComponent("LegacyWritingAwareness", isDirectory: true)
        stateURL = rootDirectory.appendingPathComponent("state.json")
        seedURL = rootDirectory.appendingPathComponent("seed.json")
        memoDirectory = rootDirectory.appendingPathComponent("VoiceMemos", isDirectory: true)
        if migrateLegacyStorage {
            migrateLegacyStorageIfNeeded()
        }
        ensureDirectories()
    }

    var storageDirectory: URL {
        rootDirectory
    }

    func loadState() -> WritingAwarenessState {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return .empty()
        }

        do {
            let data = try Data(contentsOf: stateURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WritingAwarenessState.self, from: data)
        } catch {
            print("⚠️ Failed to load writing-awareness state: \(error)")
            return .empty()
        }
    }

    func saveState(_ state: WritingAwarenessState) {
        ensureDirectories()

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(state)
            let tempURL = stateURL.appendingPathExtension("tmp")
            try data.write(to: tempURL, options: .atomic)
            if fileManager.fileExists(atPath: stateURL.path) {
                _ = try fileManager.replaceItemAt(stateURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: stateURL)
            }
        } catch {
            print("⚠️ Failed to save writing-awareness state: \(error)")
        }
    }

    func loadSharedSeed() -> WritingAwarenessSeed? {
        guard fileManager.fileExists(atPath: seedURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: seedURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WritingAwarenessSeed.self, from: data)
        } catch {
            print("⚠️ Failed to load shared writing-awareness seed: \(error)")
            return nil
        }
    }

    func syncSeed(_ seed: WritingAwarenessSeed) {
        ensureDirectories()

        if let existing = loadSharedSeed(), existing.sourceRunId == seed.sourceRunId {
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(seed)
            let tempURL = seedURL.appendingPathExtension("tmp")
            try data.write(to: tempURL, options: .atomic)
            if fileManager.fileExists(atPath: seedURL.path) {
                _ = try fileManager.replaceItemAt(seedURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: seedURL)
            }
        } catch {
            print("⚠️ Failed to sync writing-awareness seed: \(error)")
        }
    }

    func nextMemoURL() -> URL {
        ensureDirectories()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fileName = "memo-\(formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")).m4a"
        return memoDirectory.appendingPathComponent(fileName)
    }

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: memoDirectory, withIntermediateDirectories: true)
    }

    private func migrateLegacyStorageIfNeeded() {
        guard !fileManager.fileExists(atPath: stateURL.path),
              fileManager.fileExists(atPath: legacyRootDirectory.path) else {
            return
        }

        ensureDirectories()

        let legacyStateURL = legacyRootDirectory.appendingPathComponent("state.json")
        let legacyMemoDirectory = legacyRootDirectory.appendingPathComponent("VoiceMemos", isDirectory: true)

        if fileManager.fileExists(atPath: legacyStateURL.path) {
            try? fileManager.copyItem(at: legacyStateURL, to: stateURL)
        }

        if fileManager.fileExists(atPath: legacyMemoDirectory.path),
           let memoFiles = try? fileManager.contentsOfDirectory(at: legacyMemoDirectory, includingPropertiesForKeys: nil) {
            for fileURL in memoFiles {
                let destination = memoDirectory.appendingPathComponent(fileURL.lastPathComponent)
                if !fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.copyItem(at: fileURL, to: destination)
                }
            }
        }
    }
}
