public actor Event<T: Sendable> {
    private var subscribers: [EventSubscriber<T>] = []

    public func subscribe(for subscriber: some AnyObject, handler: @escaping EventHandler<T>) {
        unsubscribe(for: subscriber) // Remove any existing subscription for the same object
        subscribers.append(EventSubscriber(subscriber: subscriber, handler: handler))
    }

    public func unsubscribe(for subscriber: some AnyObject) {
        subscribers.removeAll { $0.subscriber === subscriber }
    }

    /// Fires an event with the given value, but does not wait for handlers to complete
    public func fire(with value: T) {
        Task {
            await fireAndWait(with: value)
        }
    }
    
    /// Fires an event and waits for all handlers to complete
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

    private func cleanup() {
        subscribers.removeAll { $0.subscriber == nil }
    }
}

public extension Event where T == Void {
    func subscribe(for subscriber: some AnyObject, handler: @Sendable @escaping () async -> Void) {
        subscribe(for: subscriber, handler: { _ in await handler() })
    }

    func fire() {
        fire(with: ())
    }
    
    func fireAndWait() async {
        await fireAndWait(with: ())
    }
}