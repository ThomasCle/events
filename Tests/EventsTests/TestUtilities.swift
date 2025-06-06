@testable import Events
import Foundation
import Testing

// MARK: - Test Helper Actors

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
