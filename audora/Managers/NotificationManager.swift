import Foundation
import UserNotifications
import EventKit
import Combine

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        requestAuthorization()
        setupBindings()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    private func setupBindings() {
        // Observe upcoming events from CalendarManager
        CalendarManager.shared.$upcomingEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                self?.scheduleNotifications(for: events)
            }
            .store(in: &cancellables)

        // Observe setting changes to clear/reschedule
        // Note: We'd ideally observe the UserDefaults key directly or have a publisher in UserDefaultsManager
        // For now, we rely on the fact that changing the setting usually triggers a refresh or we can check at schedule time
    }

    private func scheduleNotifications(for events: [EKEvent]) {
        guard UserDefaultsManager.shared.notifyScheduledMeetings else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        for event in events {
            // Schedule 1 minute before
            let notificationDate = event.startDate.addingTimeInterval(-60)

            if notificationDate > Date() {
                let content = UNMutableNotificationContent()
                content.title = "Upcoming Meeting"
                content.body = "\(event.title ?? "Meeting") starts in 1 minute."
                content.sound = .default

                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notificationDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

                let request = UNNotificationRequest(identifier: event.eventIdentifier, content: content, trigger: trigger)

                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("Error scheduling notification: \(error)")
                    }
                }
            }
        }
    }

    func updateSchedule() {
        // Trigger a reschedule based on current events
        scheduleNotifications(for: CalendarManager.shared.upcomingEvents)
    }
}
