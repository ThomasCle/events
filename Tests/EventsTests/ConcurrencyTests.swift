@testable import Events
import Foundation
import Testing

@Suite
struct ConcurrencyTests {
    
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
    func testConcurrentSubscribeUnsubscribe() async {
        let event = Event<Int>()
        let operationCount = 100
        let subscriberCount = 50
        
        actor TestTracker {
            private var completedOperations = 0
            private var receivedEvents = 0
            private var errors: [String] = []
            
            func recordOperation() {
                completedOperations += 1
            }
            
            func recordEvent() {
                receivedEvents += 1
            }
            
            func recordError(_ error: String) {
                errors.append(error)
            }
            
            func getStats() -> (operations: Int, events: Int, errors: [String]) {
                (completedOperations, receivedEvents, errors)
            }
        }
        
        let tracker = TestTracker()
        
        // Create a pool of subscribers that will be reused
        let subscribers = (0..<subscriberCount).map { _ in Subscriber() }
        
        // Create concurrent tasks that rapidly subscribe and unsubscribe
        await withTaskGroup(of: Void.self) { group in
            
            // Task 1: Rapid subscribe/unsubscribe operations
            for i in 0..<operationCount {
                group.addTask {
                    let subscriber = subscribers[i % subscriberCount]
                    
                    // Subscribe
                    await event.subscribe(for: subscriber) { value in
                        await tracker.recordEvent()
                    }
                    
                    // Small random delay to create timing variations
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 100_000...1_000_000)) // 0.1-1ms
                    
                    // Unsubscribe
                    await event.unsubscribe(for: subscriber)
                    
                    await tracker.recordOperation()
                }
            }
            
            // Task 2: Concurrent event firing while subscribe/unsubscribe happens
            for i in 0..<operationCount {
                group.addTask {
                    // Small delay to let some subscriptions happen first
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 500_000...2_000_000)) // 0.5-2ms
                    
                    await event.fire(with: i)
                    await tracker.recordOperation()
                }
            }
            
            // Task 3: Subscribe multiple times to same subscriber (should handle replacement)
            for i in 0..<subscriberCount {
                group.addTask {
                    let subscriber = subscribers[i]
                    
                    // Subscribe multiple times - each should replace the previous
                    for _ in 0..<5 {
                        await event.subscribe(for: subscriber) { value in
                            await tracker.recordEvent()
                        }
                        try? await Task.sleep(nanoseconds: UInt64.random(in: 100_000...500_000))
                    }
                    
                    await tracker.recordOperation()
                }
            }
            
            // Task 4: Rapid unsubscribe of non-existent or already unsubscribed subscribers
            for i in 0..<operationCount {
                group.addTask {
                    let subscriber = subscribers[i % subscriberCount]
                    
                    // Try to unsubscribe (may or may not be subscribed)
                    await event.unsubscribe(for: subscriber)
                    
                    // Try again (should be no-op)
                    await event.unsubscribe(for: subscriber)
                    
                    await tracker.recordOperation()
                }
            }
        }
        
        // Wait for any remaining events to process
        await event.waitForPendingEvents()
        
        // Get final statistics
        let (operations, events, errors) = await tracker.getStats()
        
        print("🔄 Concurrent Subscribe/Unsubscribe Results:")
        print("   Completed operations: \(operations)")
        print("   Events processed: \(events)")
        print("   Errors encountered: \(errors.count)")
        if !errors.isEmpty {
            print("   Error details: \(errors.prefix(5))") // Show first 5 errors
        }
        
        // Verify system stability - no crashes and reasonable operation completion
        #expect(errors.isEmpty, "No errors should occur during concurrent operations: \(errors)")
        
        let expectedOperations = operationCount * 3 + subscriberCount // Task 1, 2, 4 each have operationCount tasks + Task 3 has subscriberCount tasks
        #expect(operations == expectedOperations, "All operations should complete: \(operations)/\(expectedOperations)")
        
        // Final state verification - ensure event system is still functional
        let finalTestSubscriber = Subscriber()
        let finalTestState = TestState<Int>()
        
        await event.subscribe(for: finalTestSubscriber) { value in
            await finalTestState.set(value)
        }
        
        await event.fireAndWait(with: 999)
        #expect(await finalTestState.get() == 999, "Event system should still be functional after concurrent operations")
        
        // Clean up
        await event.unsubscribe(for: finalTestSubscriber)
    }
}
