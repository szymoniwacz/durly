#if MANUAL_TESTS
import Foundation

class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T,
    file: StaticString = #file, line: UInt = #line) {
    precondition(actual == expected, "Expected \(expected), got \(actual)", file: file, line: line)
}
func XCTAssertEqual(_ actual: Double, _ expected: Double, accuracy: Double,
    file: StaticString = #file, line: UInt = #line) {
    precondition(abs(actual - expected) <= accuracy, "Expected \(expected), got \(actual)", file: file, line: line)
}
func XCTAssertNil<T>(_ actual: T?, file: StaticString = #file, line: UInt = #line) {
    precondition(actual == nil, "Expected nil", file: file, line: line)
}
func XCTAssertTrue(_ actual: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(actual, "Expected true", file: file, line: line)
}
@main
struct ManualRunner {
    static func main() {
        let tests = BatteryTests()
        tests.testSeparatesDisplayedAndRawPercentagesAndDecodesSignedCurrent()
        tests.testMissingAndInvalidValuesAreNotInvented()
        tests.testMockProviderAndStaleness()
        print("PASS: 3 battery telemetry tests")
    }
}
#endif
