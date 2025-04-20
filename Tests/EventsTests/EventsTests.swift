@testable import Events
import Foundation
import Testing

@Suite
struct EventTests {
    actor Subscriber {}
    
    actor TestState<T> {
        var value: T?
        
        func set(_ newValue: T?) {
            value = newValue
        }
        
        func get() -> T? {
            value
        }
    }
    
    actor CounterState {
        private(set) var count: Int = 0
        
        func increment() {
            count += 1
        }
        
        func increment(by amount: Int) {
            count += amount
        }
    }
    
    actor ArrayState<T> {
        private(set) var values: [T] = []
        
        func append(_ value: T) {
            values.append(value)
        }
    }

    @Test
    func testSubscribeAndFire() async {
        let event = Event<Int>()
        let state = TestState<Int>()
        
        let subscriber = Subscriber()
        await event.subscribe(for: subscriber) { value in
            await state.set(value)
        }
        
        await event.fireAndWait(with: 42)
        
        #expect(await state.get() == 42)
    }
    
    @Test
    func testUnsubscribe() async {
        let event = Event<String>()
        let state = TestState<String>()
        
        let subscriber = Subscriber()
        await event.subscribe(for: subscriber) { value in
            await state.set(value)
        }
        
        await event.fireAndWait(with: "test")
        #expect(await state.get() == "test")
        
        await event.unsubscribe(for: subscriber)
        await state.set(nil)
        await event.fireAndWait(with: "test2")
        #expect(await state.get() == nil)
    }
    
    @Test
    func testMultipleSubscribers() async {
        let event = Event<Int>()
        let state = ArrayState<Int>()
        
        let subscriber1 = Subscriber()
        let subscriber2 = Subscriber()
        
        await event.subscribe(for: subscriber1) { value in
            await state.append(value * 10)
        }
        
        await event.subscribe(for: subscriber2) { value in
            await state.append(value * 100)
        }
        
        await event.fireAndWait(with: 5)
        
        let values = await state.values
        #expect(values.sorted() == [50, 500])
    }
    
    @Test
    func testSubscriberCleanup() async {
        let event = Event<String>()
        let counter = CounterState()
        
        // Create a temporary subscriber in its own scope
        do {
            // Create a subscriber that will be deallocated
            let tempSubscriber = Subscriber()
            await event.subscribe(for: tempSubscriber) { _ in
                await counter.increment()
            }
            
            // Fire once while subscriber exists
            await event.fireAndWait(with: "test")
            #expect(await counter.count == 1)
            
            // tempSubscriber will be deallocated here when leaving the scope
        }
        
        // Force any pending deallocations to complete
        for _ in 1 ... 5 {
            await Task.yield()
        }
        
        // Fire again after subscriber is deallocated
        await event.fireAndWait(with: "test")
        #expect(await counter.count == 1, "Count should not increase as subscriber was cleaned up")
    }
    
    @Test
    func testPreventDuplicateSubscription() async {
        let event = Event<Int>()
        let counter = CounterState()
        
        let subscriber = Subscriber()
        
        // Subscribe the same object twice
        await event.subscribe(for: subscriber) { _ in
            await counter.increment()
        }
        
        await event.subscribe(for: subscriber) { _ in
            await counter.increment(by: 10) // This handler should replace the first one
        }
        
        await event.fireAndWait(with: 1)
        
        // Now we expect the second handler to be active (which increments by 10)
        let value = await counter.count
        #expect(value == 10, "Only the second subscription should be active")
    }
    
    @Test
    func testVoidEvent() async {
        let event = Event<Void>()
        let counter = CounterState()
        
        let subscriber = Subscriber() // Create a strong reference to the subscriber
        await event.subscribe(for: subscriber) { _ in
            await counter.increment()
        }
        
        await event.fireAndWait()
        
        #expect(await counter.count == 1)
    }
    
    @Test
    func testVoidEventWithParameterlessHandler() async {
        let event = Event<Void>()
        let counter = CounterState()
        
        let subscriber = Subscriber()
        
        // Test the specific extension method that takes a parameterless handler
        await event.subscribe(for: subscriber) {
            await counter.increment()
        }
        
        await event.fireAndWait()
        #expect(await counter.count == 1)
        
        await event.fire()
        // Give some time for the non-waiting fire to complete
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(await counter.count == 2)
    }
    
    @Test
    func testMultipleUnsubscriptions() async {
        let event = Event<String>()
        let counter = CounterState()
        
        // Create multiple subscribers
        let subscriber1 = Subscriber()
        let subscriber2 = Subscriber()
        let subscriber3 = Subscriber()
        
        // Subscribe all of them
        await event.subscribe(for: subscriber1) { _ in
            await counter.increment()
        }
        
        await event.subscribe(for: subscriber2) { _ in
            await counter.increment()
        }
        
        await event.subscribe(for: subscriber3) { _ in
            await counter.increment()
        }
        
        // Fire once to verify all are subscribed
        await event.fireAndWait(with: "test")
        #expect(await counter.count == 3)
        
        // Unsubscribe one
        await event.unsubscribe(for: subscriber2)
        await counter.increment(by: -3) // Reset counter
        
        await event.fireAndWait(with: "test")
        #expect(await counter.count == 2, "Only two subscribers should remain")
        
        // Unsubscribe same subscriber again (should be no-op)
        await event.unsubscribe(for: subscriber2)
        await counter.increment(by: -2) // Reset counter
        
        await event.fireAndWait(with: "test")
        #expect(await counter.count == 2, "Unsubscribing again should have no effect")
        
        // Unsubscribe non-existent subscriber (should be no-op)
        let nonSubscriber = Subscriber()
        await event.unsubscribe(for: nonSubscriber)
        await counter.increment(by: -2) // Reset counter
        
        await event.fireAndWait(with: "test")
        #expect(await counter.count == 2, "Unsubscribing non-existent subscriber should have no effect")
        
        // Unsubscribe all remaining subscribers
        await event.unsubscribe(for: subscriber1)
        await event.unsubscribe(for: subscriber3)
        await counter.increment(by: -2) // Reset counter
        
        await event.fireAndWait(with: "test")
        #expect(await counter.count == 0, "No subscribers should remain")
    }
    
    @Test
    func testAsyncEventHandling() async {
        let event = Event<Int>()
        let subscriber = Subscriber()
        
        let counter = CounterState()
        
        await event.subscribe(for: subscriber) { value in
            // Simulate async work in the handler
            Task {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000 ... 10_000_000))
                await counter.increment(by: value)
            }
        }
        
        // Fire multiple events in quick succession
        for i in 1 ... 5 {
            await event.fireAndWait(with: i)
        }
        
        // Wait for all async handlers to complete
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify all events were processed
        let finalValue = await counter.count
        #expect(finalValue == 15) // 1+2+3+4+5
    }
    
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
    func testConcurrentSubscribeAndFire() async {
        let event = Event<Int>()
        let counter = CounterState()
        
        // Create subscribers first and keep references to them
        var subscribers = [Subscriber]()
        for _ in 0 ..< 50 {
            subscribers.append(Subscriber())
        }
        
        // Subscribe all subscribers
        for subscriber in subscribers {
            await event.subscribe(for: subscriber) { _ in
                await counter.increment()
            }
        }
        
        // Now fire events
        for i in 1 ... 50 {
            await event.fireAndWait(with: i)
        }
        
        let finalCount = await counter.count
        #expect(finalCount == 50 * 50, "Each event should be handled by each subscriber")
    }
    
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
}
