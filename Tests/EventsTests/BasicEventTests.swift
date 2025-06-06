@testable import Events
import Foundation
import Testing

@Suite
struct BasicEventTests {
    
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
}
