/// A type that represents an asynchronous event handler function.
///
/// `EventHandler` is a function type that takes a value of type `T` and returns `Void` asynchronously.
/// It is used for handling events in the event-subscription system.
///
/// - Parameter T: The type of data that this handler will receive when an event is fired.
///               Must conform to the `Sendable` protocol to ensure thread safety in concurrent contexts.
///
/// Usage example:
/// ```swift
/// let handler: EventHandler<String> = { message in
///     await processMessage(message)
/// }
/// ```
public typealias EventHandler<T> = @Sendable (T) async -> Void