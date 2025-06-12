import EventKit
import Foundation
import FoundationModels

struct FindFreeTimeTool: Tool {
    private enum Constants {
        static let maxTimeSlots = 3
    }
        
    var name: String { "find_free_time" }
    var description: String {
        """
        Search the user’s primary calendar for the next open windows that are at
        least `durationMinutes` long, within the next `windowHours`. Returns up
        to three ISO‑8601 start/end pairs.
        """
    }

    @Generable
    struct Arguments: Codable {
        @Guide(description: "Desired meeting length, in minutes – between 15 and 240.")
        var durationMinutes: Int

        @Guide(description: "How far ahead to search, in hours – up to 720 (30 days).")
        var windowHours: Int
    }

    @Generable(description: "FreeTimeSlot")
    struct Result: Codable {
        let startISO8601: String
        let endISO8601: String
    }

    // MARK: - Call
    func call(arguments: Arguments) async throws -> ToolOutput {
        let store = EKEventStore()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestFullAccessToEvents { granted, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if !granted {
                    continuation.resume(
                        throwing: NSError(
                            domain: "EKEventStore",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Access to calendar events was not granted."]
                        )
                    )
                } else {
                    continuation.resume()
                }
            }
        }

        let duration = max(15, min(arguments.durationMinutes, 240))
        let windowHrs = max(1, min(arguments.windowHours, 720))
        let windowEnd = Calendar.current.date(byAdding: .hour, value: windowHrs, to: .now)!

        let predicate = store.predicateForEvents(
            withStart: .now,
            end: windowEnd,
            calendars: nil
        )
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        var cursor = Date()
        var slots: [Result] = []

        for event in events {
            let gap = event.startDate.timeIntervalSince(cursor)
            if gap >= TimeInterval(duration * 60) {
                slots.append(
                    Result(
                        startISO8601: cursor.iso8601String,
                        endISO8601: event.startDate.iso8601String
                    )
                )
            }
            cursor = max(cursor, event.endDate)
            
            if slots.count == Constants.maxTimeSlots {
                break
            }
        }

        if slots.count < Constants.maxTimeSlots,
           windowEnd.timeIntervalSince(cursor) >= TimeInterval(duration * 60) {
            slots.append(
                Result(
                    startISO8601: cursor.iso8601String,
                    endISO8601: windowEnd.iso8601String
                )
            )
        }
        
        return ToolOutput(slots.map(\.startISO8601).joined(separator: "\n"))
    }
}

private extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}

