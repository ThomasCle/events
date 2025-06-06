/// An actor that implements a type-safe event system with weak references to subscribers.
///
/// `Event` provides a way to implement the observer pattern in Swift with built-in
/// support for concurrency through Swift's actors. It allows objects to subscribe to events,
/// receive notifications when events are fired, and automatically manages the lifecycle of
/// subscribers through weak references.
///
/// Example usage:
/// ```swift
/// // Create an event that passes String values
/// let nameChangedEvent = Event<String>()
///
/// // Subscribe to the event
/// await nameChangedEvent.subscribe(for: self) { newName in
///     await updateUserInterface(with: newName)
/// }
///
/// // Fire the event
/// await nameChangedEvent.fire(with: "John Doe")
/// ```
///
/// - Generic Parameter T: The type of data that will be passed when an event is fired.
///                      Must conform to the `Sendable` protocol to ensure thread safety in concurrent contexts.
public actor Event<T: Sendable> {
    /// Bundles all state related to a single subscriber (except mutable pending count).
    private struct SubscriberState {
        let subscriber: EventSubscriber<T>
        let streamContinuation: AsyncStream<T>.Continuation
        let processingTask: Task<Void, Never>
    }
    
    /// Dictionary of subscriber states keyed by their ObjectIdentifier.
    private var subscriberStates: [ObjectIdentifier: SubscriberState] = [:]
    
    /// Tracks the number of events currently being processed by each subscriber.
    private var pendingEventCounts: [ObjectIdentifier: Int] = [:]

    /// Constructor for creating an event.
    public init() { }

    /// Adds a subscription for the specified object with the given handler.
    ///
    /// This method automatically removes any existing subscription for the same object
    /// before adding the new one, ensuring an object can only have one active subscription at a time.
    ///
    /// - Parameters:
    ///   - subscriber: The object subscribing to the event. A weak reference is stored to prevent retain cycles.
    ///   - handler: The function to call when the event is fired.
    /// - Note: The subscriber must be a class instance (AnyObject) so it can be weakly referenced.
    public func subscribe(for subscriber: some AnyObject, handler: @escaping EventHandler<T>) {
        let subscriberId = ObjectIdentifier(subscriber)
        
        // Clean up any dead subscribers first
        unsubscribe(for: subscriber)
        cleanup()
        
        // Create the EventSubscriber struct
        let eventSubscriber = EventSubscriber(subscriber: subscriber, handler: handler)
        
        // Create an AsyncStream for this subscriber
        let (stream, continuation) = AsyncStream.makeStream(of: T.self)
        
        // Start a task to process events from this subscriber's stream
        let processingTask = Task { [weak self] in
            for await value in stream {
                // Process the event
                await handler(value)
                
                // Decrement pending count after processing
                await self?.decrementPendingCount(for: subscriberId)
            }
        }
        
        // Bundle all subscriber state together
        let state = SubscriberState(
            subscriber: eventSubscriber,
            streamContinuation: continuation,
            processingTask: processingTask
        )
        
        subscriberStates[subscriberId] = state
        pendingEventCounts[subscriberId] = 0
    }

    /// Removes the subscription for the specified object.
    ///
    /// - Parameter subscriber: The object whose subscription should be removed.
    /// - Note: If the object has no subscription, this method has no effect.
    public func unsubscribe(for subscriber: some AnyObject) {
        let subscriberId = ObjectIdentifier(subscriber)
        guard let state = subscriberStates[subscriberId] else { return }
        
        state.processingTask.cancel()
        state.streamContinuation.finish()
        
        subscriberStates.removeValue(forKey: subscriberId)
        pendingEventCounts.removeValue(forKey: subscriberId)
    }

    /// Fires an event with the given value, but does not wait for handlers to complete.
    ///
    /// This method yields the event to all subscriber streams and returns immediately.
    /// Each subscriber processes events in order through their individual AsyncStream.
    ///
    /// - Parameter value: The value to pass to each subscriber's handler.
    /// - Note: If you need to ensure all handlers have completed, use `fireAndWait(with:)` instead.
    public func fire(with value: T) {
        cleanup()
        
        // Yield the event to all active subscriber streams and track pending events
        for (subscriberId, state) in subscriberStates {
            pendingEventCounts[subscriberId, default: 0] += 1
            state.streamContinuation.yield(value)
        }
    }

    /// Fires an event and waits for all handlers to complete.
    ///
    /// This method yields the event to all subscriber streams and waits until all
    /// subscribers have processed the event before returning. Events are processed
    /// in the same order as `fire(with:)` to maintain consistency.
    ///
    /// - Parameter value: The value to pass to each subscriber's handler.
    public func fireAndWait(with value: T) async {
        cleanup()
        
        // Yield the event to all active subscriber streams and track pending events
        for (subscriberId, state) in subscriberStates {
            pendingEventCounts[subscriberId, default: 0] += 1
            state.streamContinuation.yield(value)
        }
        
        // Wait for all events to complete processing
        await waitForPendingEvents()
    }

    /// Removes subscribers whose referenced objects have been deallocated.
    ///
    /// This method is called automatically before firing events to clean up the subscriber list.
    private func cleanup() {
        var keysToRemove: [ObjectIdentifier] = []
        
        for (key, state) in subscriberStates {
            if state.subscriber.subscriber == nil {
                keysToRemove.append(key)
            }
        }
        
        for key in keysToRemove {
            guard let state = subscriberStates[key] else { continue }
            
            // Cancel the processing task
            state.processingTask.cancel()
            
            // Finish the stream
            state.streamContinuation.finish()
            
            // Remove the subscriber state
            subscriberStates.removeValue(forKey: key)
            
            // Remove pending count tracking
            pendingEventCounts.removeValue(forKey: key)
        }
    }
    
    /// Increments the pending event count for a subscriber.
    private func incrementPendingCount(for subscriberId: ObjectIdentifier) {
        pendingEventCounts[subscriberId, default: 0] += 1
    }
    
    /// Decrements the pending event count for a subscriber.
    private func decrementPendingCount(for subscriberId: ObjectIdentifier) {
        if let count = pendingEventCounts[subscriberId], count > 0 {
            pendingEventCounts[subscriberId] = count - 1
        }
    }
    
    /// Waits for all currently pending events to complete processing.
    ///
    /// This method will wait until all events that have been fired (but not yet processed)
    /// have completed execution across all subscribers.
    public func waitForPendingEvents() async {
        while !pendingEventCounts.values.allSatisfy({ $0 == 0 }) {
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
    }
    
    /// Checks if a subscriber is still active (not deallocated)
    ///
    /// - Parameter subscriberId: The ObjectIdentifier of the subscriber to check
    /// - Returns: true if the subscriber is still alive, false otherwise
    private func isSubscriberStillActive(_ subscriberId: ObjectIdentifier) -> Bool {
        guard let state = subscriberStates[subscriberId] else { return false }
        return state.subscriber.subscriber != nil
    }
}

/// Extension providing convenience methods for events that don't need to pass any data.
public extension Event where T == Void {
    /// Adds a subscription for the specified object with a handler that doesn't require any parameters.
    ///
    /// This is a convenience method for `Void` events where the handler doesn't need to receive any value.
    ///
    /// - Parameters:
    ///   - subscriber: The object subscribing to the event. A weak reference is stored to prevent retain cycles.
    ///   - handler: The parameterless function to call when the event is fired.
    func subscribe(for subscriber: some AnyObject, handler: @Sendable @escaping () async -> Void) {
        subscribe(for: subscriber) { _ in await handler() }
    }

    /// Fires a `Void` event without any associated value.
    ///
    /// This is a convenience method for firing events that don't need to pass any data.
    func fire() {
        fire(with: ())
    }

    /// Fires a `Void` event and waits for all handlers to complete.
    ///
    /// This is a convenience method for firing events that don't need to pass any data,
    /// but where you need to ensure all handlers have completed before continuing.
    func fireAndWait() async {
        await fireAndWait(with: ())
    }
}
