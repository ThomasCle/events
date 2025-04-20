/// A structure that holds a reference to a subscriber object and its event handler.
///
/// `EventSubscriber` uses weak references to avoid retain cycles between the event system
/// and subscriber objects. It's designed to be used internally by the `Event` actor.
///
/// - Generic Parameter T: The type of data that this subscriber's handler will receive when an event is fired.
///                       Must conform to the `Sendable` protocol to ensure thread safety in concurrent contexts.
struct EventSubscriber<T: Sendable> {
    /// A weak reference to the subscriber object to prevent retain cycles.
    /// When the original object is deallocated, this reference becomes `nil`.
    weak var subscriber: AnyObject?

    /// The handler function that will be called when an event is fired.
    var handler: EventHandler<T>?

    /// Creates a new event subscriber.
    ///
    /// - Parameters:
    ///   - subscriber: The object subscribing to events. Stored as a weak reference to prevent retain cycles.
    ///   - handler: The function to call when an event is fired. Default is `nil`.
    init(subscriber: AnyObject, handler: EventHandler<T>? = nil) {
        self.subscriber = subscriber
        self.handler = handler
    }
}
