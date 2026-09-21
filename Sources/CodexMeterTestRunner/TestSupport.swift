import Foundation

/// Minimal test harness entry: a named, async test closure.
struct TestEntry {
    let name: String
    let run: () async throws -> Void
}

func sync(_ body: @escaping () throws -> Void) -> () async throws -> Void {
    { try body() }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func expectTrue(_ condition: Bool, _ message: String) throws {
    guard condition else { throw TestFailure(message) }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") throws {
    guard actual == expected else {
        throw TestFailure("\(message.isEmpty ? "expectEqual" : message): actual=\(actual) expected=\(expected)")
    }
}

func expectNil<T>(_ value: T?, _ message: String = "") throws {
    guard value == nil else { throw TestFailure("\(message.isEmpty ? "expectNil" : message): got \(value!)") }
}

func expectNotNil<T>(_ value: T?, _ message: String = "") throws -> T {
    guard let value else {
        throw TestFailure("\(message.isEmpty ? "expectNotNil" : message): got nil")
    }
    return value
}
