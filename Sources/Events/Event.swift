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
    /// Collection of subscribers to this event.
    private var subscribers: [EventSubscriber<T>] = []

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
        unsubscribe(for: subscriber) // Remove any existing subscription for the same object
        subscribers.append(EventSubscriber(subscriber: subscriber, handler: handler))
    }

    /// Removes the subscription for the specified object.
    ///
    /// - Parameter subscriber: The object whose subscription should be removed.
    /// - Note: If the object has no subscription, this method has no effect.
    public func unsubscribe(for subscriber: some AnyObject) {
        subscribers.removeAll { $0.subscriber === subscriber }
    }

    /// Fires an event with the given value, but does not wait for handlers to complete.
    ///
    /// This method launches a new task to process all subscriber handlers and returns immediately.
    ///
    /// - Parameter value: The value to pass to each subscriber's handler.
    /// - Note: If you need to ensure all handlers have completed, use `fireAndWait(with:)` instead.
    public func fire(with value: T) {
        Task {
            await fireAndWait(with: value)
        }
    }
    
    /// Fires an event and waits for all handlers to complete.
    ///
    /// This method waits until all subscriber handlers have processed the event before returning.
    /// Handlers are executed concurrently using Swift's structured concurrency.
    ///
    /// - Parameter value: The value to pass to each subscriber's handler.
    public func fireAndWait(with value: T) async {
        cleanup()
        
        await withTaskGroup(of: Void.self) { group in
            for subscriber in subscribers {
                if let handler = subscriber.handler {
                    group.addTask {
                        await handler(value)
                    }
                }
            }
        }
    }

    /// Removes subscribers whose referenced objects have been deallocated.
    ///
    /// This method is called automatically before firing events to clean up the subscriber list.
    private func cleanup() {
        subscribers.removeAll { $0.subscriber == nil }
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
        subscribe(for: subscriber, handler: { _ in await handler() })
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