struct EventSubscriber<T: Sendable> {
    weak var subscriber: AnyObject?
    var handler: EventHandler<T>?
    
    init(subscriber: AnyObject, handler: EventHandler<T>? = nil) {
        self.subscriber = subscriber
        self.handler = handler
    }
}