//
//  CalendarPersistenceManager.swift
//  audora
//
//  Created by Tony Tran on 2026-03-12.
//

//// Observe in a view:
//@StateObject var persistence = CalendarPersistenceManager.shared

import Foundation
import EventKit
import SwiftUI

// MARK: - Codable snapshot of an EKEvent (only the fields we care about)

struct PersistedEvent: Codable, Identifiable {
    let id: String          // eventIdentifier
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarIdentifier: String
    let location: String?
    let notes: String?
    let urlString: String?
    let attendeeCount: Int

    init(event: EKEvent) {
        self.id                 = event.eventIdentifier ?? UUID().uuidString
        self.title              = event.title ?? "(No title)"
        self.startDate          = event.startDate
        self.endDate            = event.endDate
        self.calendarIdentifier = event.calendar?.calendarIdentifier ?? ""
        self.location           = event.location
        self.notes              = event.notes
        self.urlString          = event.url?.absoluteString
        self.attendeeCount      = event.attendees?.count ?? 0
    }
}

// MARK: - CalendarPersistenceManager

/// Continuously listens for calendar store changes, fetches the next 7 days of
/// events, merges them into a local cache (deduplicating on `eventIdentifier`),
/// and writes the cache to disk so it survives app restarts.
class CalendarPersistenceManager: ObservableObject {

    static let shared = CalendarPersistenceManager()

    // MARK: Published state

    @Published var persistedEvents: [PersistedEvent] = []

    // MARK: Private

    private let eventStore = EKEventStore()
    private var storeObserver: NSObjectProtocol?

    /// File URL where events are cached as JSON.
    private let cacheURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
        let dir = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "CalendarApp",
                                                 isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir.appendingPathComponent("persisted_events.json")
    }()

    private init() {
        print("Cache file:", cacheURL)
        loadFromDisk()
        startObserving()
        self.printCacheJSON()
    }

    deinit {
        stopObserving()
    }

    // MARK: - Public API

    /// Call once on launch (or after the user grants calendar access) to start
    /// the live-update cycle. Safe to call multiple times.
    func activate() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .authorized {
            fetchAndMerge()
        }
    }

    // MARK: - Observer lifecycle

    private func startObserving() {
        guard storeObserver == nil else { return }

        // EKEventStoreChangedNotification fires whenever *any* calendar data changes
        // (new/modified/deleted events, calendar added, iCloud sync, etc.)
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            self?.fetchAndMerge()
        }
    }

    private func stopObserving() {
        if let obs = storeObserver {
            NotificationCenter.default.removeObserver(obs)
            storeObserver = nil
        }
    }

    // MARK: - Fetch + merge

    private func fetchAndMerge() {
        guard EKEventStore.authorizationStatus(for: .event) == .authorized else { return }

        let now     = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: nil)
        let fresh = eventStore.events(matching: predicate)

        // Build a dictionary of fresh events keyed by identifier
        var freshMap: [String: EKEvent] = [:]
        for event in fresh {
            guard let id = event.eventIdentifier, !id.isEmpty else { continue }
            freshMap[id] = event
        }

        // Build a dictionary of currently persisted events for comparison
        let existingMap: [String: PersistedEvent] = Dictionary(
            uniqueKeysWithValues: persistedEvents.map { ($0.id, $0) }
        )

        // Detect created events — in fresh but not in existing
        for (id, event) in freshMap {
            if existingMap[id] == nil {
                print("[Calendar] ✅ Created: \(event.title ?? "Untitled") — \(event.startDate)")
            }
        }

        // Detect deleted events — in existing but not in fresh (within the fetch window)
        for (id, existing) in existingMap {
            let isInWindow = existing.startDate >= now && existing.startDate <= endDate
            if isInWindow && freshMap[id] == nil {
                print("[Calendar] ❌ Deleted: \(existing.title) — \(existing.startDate)")
            }
        }

        // Detect updated events — in both, but something changed
        for (id, event) in freshMap {
            if let existing = existingMap[id] {
                var changes: [String] = []
                if existing.title != (event.title ?? "Untitled")   { changes.append("title") }
                if existing.startDate != event.startDate           { changes.append("startDate") }
                if existing.endDate != event.endDate               { changes.append("endDate") }
                if existing.location != event.location             { changes.append("location") }
                if existing.notes != event.notes                   { changes.append("notes") }
                if existing.attendeeCount != event.attendees?.count ?? 0 { changes.append("attendees") }

                if !changes.isEmpty {
                    print("[Calendar] ✏️ Updated: \(event.title ?? "Untitled") — changed: \(changes.joined(separator: ", "))")
                }
            }
        }

        // --- rest of your existing merge logic below ---
        var merged: [String: PersistedEvent] = [:]
        for pe in persistedEvents {
            if pe.startDate < now || pe.startDate > endDate {
                merged[pe.id] = pe
            }
        }
        for (id, event) in freshMap {
            merged[id] = PersistedEvent(event: event)
        }

        let sorted = merged.values.sorted { $0.startDate < $1.startDate }

        DispatchQueue.main.async {
            self.persistedEvents = sorted
            self.saveToDisk(sorted)
            self.printCacheJSON()
        }
    }

    // MARK: - Persistence

    private func saveToDisk(_ events: [PersistedEvent]) {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("[CalendarPersistenceManager] Save error: \(error)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        do {
            let data = try Data(contentsOf: cacheURL)
            let events = try JSONDecoder().decode([PersistedEvent].self, from: data)
            self.persistedEvents = events
        } catch {
            print("[CalendarPersistenceManager] Load error: \(error)")
        }
    }
    
    private func printCacheJSON() {
        do {
            let data = try Data(contentsOf: cacheURL)
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted])
                if let prettyString = String(data: prettyData, encoding: .utf8) {
                    print("[CalendarPersistenceManager] JSON contents:\n\(prettyString)")
                }
            } else {
                print("[CalendarPersistenceManager] File exists but is not valid JSON")
            }
        } catch {
            print("[CalendarPersistenceManager] Could not read JSON for printing: \(error)")
        }
    }
}
