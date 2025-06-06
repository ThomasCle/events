@testable import Events
import Foundation
import Testing

@Suite
struct EventOrderingTests {
    
    @Test
    func testEventChaining() async {
        let sourceEvent = Event<Int>()
        let derivedEvent = Event<Int>()
        
        let sourceValues = ArrayState<Int>()
        let derivedValues = ArrayState<Int>()
        
        // Use strong references to subscribers
        let sourceSubscriber = Subscriber()
        let derivedSubscriber = Subscriber()
        
        // Chain events: when sourceEvent fires, it triggers derivedEvent with transformed value
        await sourceEvent.subscribe(for: sourceSubscriber) { value in
            await sourceValues.append(value)
            // Use a direct await instead of spawning a Task
            await derivedEvent.fireAndWait(with: value * 2)
        }
        
        await derivedEvent.subscribe(for: derivedSubscriber) { value in
            await derivedValues.append(value)
        }
        
        for i in 1 ... 5 {
            await sourceEvent.fireAndWait(with: i)
        }
        
        #expect(await sourceValues.values == [1, 2, 3, 4, 5])
        #expect(await derivedValues.values == [2, 4, 6, 8, 10])
    }
    
    @Test
    func testFireWithoutWaiting() async {
        let event = Event<String>()
        let state = TestState<String>()
        
        let subscriber = Subscriber()
        await event.subscribe(for: subscriber) { value in
            // Simulate slow handler
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await state.set(value)
        }
        
        // Fire without waiting
        await event.fire(with: "test")
        
        // Check immediately - handler should not have completed yet
        #expect(await state.get() == nil)
        
        // Wait enough time for the handler to complete
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Now the handler should have completed
        #expect(await state.get() == "test")
    }
    
    @Test
    func testHighFrequencyFiringOrder() async {
        let event = Event<Int>()
        let eventCount = 100
        
        actor OrderTracker {
            private var receivedEvents: [Int] = []
            
            func recordEvent(_ value: Int) {
                receivedEvents.append(value)
            }
            
            func getReceivedEvents() -> [Int] {
                receivedEvents
            }
        }
        
        let tracker = OrderTracker()
        let subscriber = Subscriber()
        
        // Subscribe to track the order of received events
        await event.subscribe(for: subscriber) { value in
            // Simulate variable processing time
            try? await Task.sleep(for: .milliseconds(Double.random(in: 10...100))) 
            await tracker.recordEvent(value)
        }
        
        // Fire events rapidly WITHOUT waiting for each to complete
        for i in 1...eventCount {
            await event.fire(with: i)
        }
        
        // Wait for all events to be processed
        await event.waitForPendingEvents()
        
        // Verify that events were received in the same order they were fired
        let receivedEvents = await tracker.getReceivedEvents()
        let expectedEvents = Array(1...eventCount)
        
        #expect(receivedEvents.count == eventCount, "Should receive all \(eventCount) events")
        #expect(receivedEvents == expectedEvents, "Events should be received in the same order they were fired: expected \(expectedEvents), but got \(receivedEvents)")
    }
    
    @Test
    func testOrderingConsistencyBetweenFireMethods() async {
        let event = Event<String>()
        
        actor OrderTracker {
            private var events: [String] = []
            
            func add(_ event: String) {
                events.append(event)
            }
            
            func getEvents() -> [String] {
                return events
            }
        }
        
        let tracker = OrderTracker()
        let subscriber = Subscriber()
        
        await event.subscribe(for: subscriber) { value in
            // Add small delay to ensure ordering matters
            try? await Task.sleep(for: .milliseconds(10))
            await tracker.add(value)
        }
        
        // Mix fire() and fireAndWait() calls to test ordering consistency
        await event.fire(with: "first")
        await event.fireAndWait(with: "second")  // Should come after "first"
        await event.fire(with: "third")
        await event.fireAndWait(with: "fourth")  // Should come after "third"
        
        // Wait for all to complete
        await event.waitForPendingEvents()
        
        let receivedEvents = await tracker.getEvents()
        let expectedOrder = ["first", "second", "third", "fourth"]
        
        #expect(receivedEvents == expectedOrder, "Mixed fire() and fireAndWait() calls should maintain order: expected \(expectedOrder), but got \(receivedEvents)")
    }
}
