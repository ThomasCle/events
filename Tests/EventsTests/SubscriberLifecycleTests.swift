@testable import Events
import Foundation
import Testing

@Suite
struct SubscriberLifecycleTests {
    
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
}
