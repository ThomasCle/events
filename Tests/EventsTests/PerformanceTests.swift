@testable import Events
import Foundation
import Testing

@Suite
struct PerformanceTests {
    
    @Test
    func testHighFrequencyFiring() async {
        let event = Event<Int>()
        let eventCount = 100
        let subscriberCount = 10
        
        actor EventCounter {
            private var counts = [Int: Int]()
            
            func record(id: Int, value: Int) {
                counts[id, default: 0] += value
            }
            
            func getCounts() -> [Int: Int] {
                counts
            }
        }
        
        let counter = EventCounter()
        var subscribers = [Subscriber]()
        
        // Create multiple subscribers
        for i in 0 ..< subscriberCount {
            let subscriber = Subscriber()
            subscribers.append(subscriber)
            
            await event.subscribe(for: subscriber) { value in
                Task {
                    // Simulate varying processing times
                    if i % 3 == 0 {
                        try? await Task.sleep(nanoseconds: 500_000)
                    }
                    await counter.record(id: i, value: value)
                }
            }
        }
        
        // Fire events rapidly and wait for each to complete
        for i in 1 ... eventCount {
            await event.fireAndWait(with: i)
        }
        
        // Wait for any nested Tasks to complete
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify results
        let counts = await counter.getCounts()
        #expect(counts.count == subscriberCount)
        
        let expectedSum = (1 ... eventCount).reduce(0, +)
        for i in 0 ..< subscriberCount {
            #expect(counts[i] == expectedSum, "Subscriber \(i) should have processed all events")
        }
    }
    
    @Test
    func testPerformanceBaseline() async {
        let event = Event<Int>()
        let eventCount = 10_000
        let subscriberCount = 1000
        let expectedTotal = eventCount * subscriberCount
        
        actor PerformanceTracker {
            private var completedEvents = 0
            private var startTime: Date?
            private var endTime: Date?
            private let targetCount: Int
            
            init(targetCount: Int) {
                self.targetCount = targetCount
            }
            
            func recordStart() {
                startTime = Date()
            }
            
            func recordEventCompletion() {
                completedEvents += 1
                if completedEvents == targetCount {
                    endTime = Date()
                }
            }
            
            func getDuration() -> TimeInterval? {
                guard let start = startTime, let end = endTime else { return nil }
                return end.timeIntervalSince(start)
            }
            
            func getCompletedCount() -> Int {
                completedEvents
            }
        }
        
        let tracker = PerformanceTracker(targetCount: expectedTotal)
        var subscribers = [Subscriber]()
        
        // Create and subscribe 1,000 subscribers
        for _ in 0..<subscriberCount {
            let subscriber = Subscriber()
            subscribers.append(subscriber)
            
            await event.subscribe(for: subscriber) { value in
                // Simulate minimal processing
                await tracker.recordEventCompletion()
            }
        }
        
        // Record start time and fire 10,000 events rapidly
        await tracker.recordStart()
        for i in 1...eventCount {
            await event.fire(with: i) // Using fire() not fireAndWait() for "fire and forget"
        }
        
        // Wait for all events to be processed (with generous timeout)
        var duration: TimeInterval?
        for _ in 0..<200 { // Check for up to 20 seconds
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms intervals
            duration = await tracker.getDuration()
            if duration != nil {
                break
            }
        }
        
        let completedCount = await tracker.getCompletedCount()
        
        print("🔥 Performance Baseline Results:")
        print("   Events fired per subscriber: \(eventCount)")
        print("   Subscribers: \(subscriberCount)")
        print("   Expected total handlers: \(expectedTotal)")
        print("   Completed handlers: \(completedCount)")
        if let duration = duration {
            print("   Total duration: \(String(format: "%.3f", duration)) seconds")
            print("   Events per subscriber per second: \(String(format: "%.0f", Double(eventCount) / duration))")
            print("   Handler executions per second: \(String(format: "%.0f", Double(completedCount) / duration))")
        } else {
            print("   ⚠️ Test timed out - not all handlers completed")
        }
        
        // Verify all handlers completed (though order may be wrong)
        #expect(completedCount == expectedTotal, "All handlers should have completed: \(completedCount)/\(expectedTotal)")
    }
}
