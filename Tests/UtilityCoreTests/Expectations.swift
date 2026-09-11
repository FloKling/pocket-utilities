import Foundation
import Testing

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, sourceLocation: sourceLocation)
}
func expectEqual(_ actual: CGFloat, _ expected: CGFloat, accuracy: CGFloat, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(actual - expected) <= accuracy, sourceLocation: sourceLocation)
}
func expectGreater<T: Comparable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(actual > expected, sourceLocation: sourceLocation) }
func expectGreaterOrEqual<T: Comparable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(actual >= expected, sourceLocation: sourceLocation) }
func expectLessOrEqual<T: Comparable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(actual <= expected, sourceLocation: sourceLocation) }
func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value, sourceLocation: sourceLocation) }
func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(!value, sourceLocation: sourceLocation) }
func expectNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value == nil, sourceLocation: sourceLocation) }
func expectNotNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value != nil, sourceLocation: sourceLocation) }
func requireValue<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T { try #require(value, sourceLocation: sourceLocation) }
func expectThrows<T>(_ expression: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(throws: (any Error).self, sourceLocation: sourceLocation) { _ = try expression() }
}
