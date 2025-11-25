import Foundation
import EventKit
import SwiftUI

class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    private let eventStore = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var calendars: [EKCalendar] = []
    @Published var upcomingEvents: [EKEvent] = []

    private init() {
        updateAuthorizationStatus()
    }

    func updateAuthorizationStatus() {
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess(completion: @escaping (Bool, Error?) -> Void) {
        eventStore.requestAccess(to: .event) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.updateAuthorizationStatus()
                if granted {
                    self?.fetchCalendars()
                }
                completion(granted, error)
            }
        }
    }

    func fetchCalendars() {
        guard authorizationStatus == .authorized else { return }
        let allCalendars = eventStore.calendars(for: .event)
        DispatchQueue.main.async {
            self.calendars = allCalendars
        }
    }

    @Published var nextEvent: EKEvent?

    func fetchUpcomingEvents(calendarIDs: Set<String>? = nil) {
        guard authorizationStatus == .authorized else { return }

        let calendarsToSearch: [EKCalendar]?
        if let calendarIDs = calendarIDs {
            calendarsToSearch = calendars.filter { calendarIDs.contains($0.calendarIdentifier) }
        } else {
            calendarsToSearch = nil // Search all
        }

        let now = Date()
        // Fetch events for the next 7 days
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: now)!

        let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: calendarsToSearch)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        // Filter events
        let showNoParticipants = UserDefaultsManager.shared.showEventsWithNoParticipants
        let filteredEvents = events.filter { event in
            if showNoParticipants { return true }
            // Check if event has participants (attendees) or a video link (location/notes/url)
            let hasAttendees = event.attendees?.isEmpty == false
            let hasVideoLink = (event.location?.contains("zoom") == true || event.location?.contains("meet") == true || event.location?.contains("teams") == true) ||
                               (event.notes?.contains("zoom") == true || event.notes?.contains("meet") == true || event.notes?.contains("teams") == true) ||
                               (event.url?.absoluteString.contains("zoom") == true || event.url?.absoluteString.contains("meet") == true || event.url?.absoluteString.contains("teams") == true)

            return hasAttendees || hasVideoLink
        }

        DispatchQueue.main.async {
            self.upcomingEvents = filteredEvents
            // Find next event (first event that hasn't ended yet)
            self.nextEvent = filteredEvents.first(where: { $0.endDate > Date() })
        }
    }
}
