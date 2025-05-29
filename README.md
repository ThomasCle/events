<img src="https://i.imgur.com/vTPmLia.jpeg" width=800 alt="Events - Concurrency-safe event broadcasting using Swift's modern actor model - Designed for simplicity. Built for Swift concurrency.">

# Events
[![Swift](https://img.shields.io/badge/Swift-6.1-orange.svg)](https://swift.org)

An ultra lightweight, type-safe Swift package for implementing the observer pattern with modern Swift concurrency support. This package provides a clean, efficient way to handle events in your Swift applications with automatic memory management and unsubscribing through weak references.

## Features

- 🔄 **Type-safe event system** - Generic implementation ensures compile-time type safety
- 🧵 **Swift Concurrency** - Built on Swift's actor model for thread safety and designed for Swift's modern concurrency model.
- 🧪 **Comprehensive testing** - Thoroughly tested for reliability
- 📚 **Minimal API** - Simple, intuitive interface with powerful capabilities.

## Requirements

- Swift 6.1+
- iOS 13.0+, macOS 10.15+, watchOS 6.0+, tvOS 13.0+ (or newer)

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/ThomasCle/events.git", from: "1.0.0")
]
```

Then add `Events` to your target dependencies:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["Events"]),
]
```

## Usage

### Minimal example
```swift
let event = Event<String>()

await event.subscribe(for: self) { value in
    print("Received value: \(value)")
}

// ...

await event.fire(with: "Hello world 🕺🏻")
```

### Detailed example

```swift
import Events

actor UserManager {
    private(set) var user: User?

    let onLogin = Event<User>()
    let onLogout = Event<Void>()
    
    func login(userName: String, password: String) async throws {
        let user = try await userService.login(username: username, password: password)
        self.user = user
        
        // Fire the event to notify subscribers
        await onLogin.fire(with: user)
    }

    func logout() async {
        user = nil

        // Fire event without value.
        await onLogout.fire()
    }
}

@Observable
final class ViewModel {
    private(set) var user: User?
    private let userManager = UserManager()

    init() {
        Task {
            await setup()
        }
    }
    
    deinit { 
        // ... no need to unsubscribe, the deallocation will throw away the subscription because `self` is the subscriber.
    }
    
    func setup() async {
        await userManager.oLogin.subscribe(for: self) { [weak self] user in
            self?.user = user
        }
    }
}
```

### Unsubscribing

```swift
// Unsubscribe when no longer needed
await userManager.onLogin.unsubscribe(for: self)
```

## Memory Management

The Events package automatically manages memory for you:

- Subscribers are held with **weak references** to prevent retain cycles
- Event system automatically cleans up references to deallocated subscribers
- No need to manually unsubscribe when objects are deallocated

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
