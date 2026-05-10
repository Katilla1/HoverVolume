import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    try expect(actual == expected, "\(message). Expected \(expected), got \(actual)")
}

func expectClose(_ actual: Float32?, _ expected: Float32?, _ message: String) throws {
    switch (actual, expected) {
    case (nil, nil):
        return
    case let (lhs?, rhs?):
        try expect(abs(lhs - rhs) < 0.0001, "\(message). Expected \(rhs), got \(lhs)")
    default:
        throw TestFailure(description: "\(message). Expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}

func runTests() throws {
    try expectClose(
        HoverVolumeLogic.volumeDelta(
            scrollingDeltaX: 0,
            scrollingDeltaY: 12,
            hasPreciseScrollingDeltas: false,
            momentumPhaseIsEmpty: true
        ),
        0.05,
        "Mouse wheel scroll up should use the fixed step"
    )

    try expectClose(
        HoverVolumeLogic.volumeDelta(
            scrollingDeltaX: 0,
            scrollingDeltaY: -12,
            hasPreciseScrollingDeltas: false,
            momentumPhaseIsEmpty: true
        ),
        -0.05,
        "Mouse wheel scroll down should use the fixed step"
    )

    try expectClose(
        HoverVolumeLogic.volumeDelta(
            scrollingDeltaX: 0,
            scrollingDeltaY: 5,
            hasPreciseScrollingDeltas: true,
            momentumPhaseIsEmpty: true
        ),
        0.02,
        "Trackpad delta should scale smoothly"
    )

    try expectClose(
        HoverVolumeLogic.volumeDelta(
            scrollingDeltaX: 0,
            scrollingDeltaY: 100,
            hasPreciseScrollingDeltas: true,
            momentumPhaseIsEmpty: true
        ),
        0.08,
        "Trackpad delta should clamp at the configured maximum"
    )

    try expectEqual(
        HoverVolumeLogic.volumeDelta(
            scrollingDeltaX: 0,
            scrollingDeltaY: 2,
            hasPreciseScrollingDeltas: true,
            momentumPhaseIsEmpty: false
        ),
        nil,
        "Momentum scrolling should be ignored"
    )

    try expectEqual(
        HoverVolumeLogic.volumeDelta(
            scrollingDeltaX: 0,
            scrollingDeltaY: 0.001,
            hasPreciseScrollingDeltas: true,
            momentumPhaseIsEmpty: true
        ),
        nil,
        "Tiny scroll input should be ignored"
    )

    try expectClose(
        HoverVolumeLogic.volumeDelta(
            scrollingDeltaX: 6,
            scrollingDeltaY: 2,
            hasPreciseScrollingDeltas: true,
            momentumPhaseIsEmpty: true
        ),
        0.008,
        "Default scrolling should prioritize vertical movement when both axes are active"
    )

    try expectClose(
        HoverVolumeLogic.volumeDelta(
            scrollingDeltaX: -10,
            scrollingDeltaY: 0,
            hasPreciseScrollingDeltas: false,
            momentumPhaseIsEmpty: true
        ),
        -0.05,
        "Default scrolling should still fall back to horizontal movement when vertical is inactive"
    )

    try expectEqual(
        HoverVolumeLogic.volumeDelta(
            scrollingDeltaX: 8,
            scrollingDeltaY: 0,
            hasPreciseScrollingDeltas: true,
            momentumPhaseIsEmpty: true,
            axisPreference: .verticalOnly
        ),
        nil,
        "Vertical-only scrolling should ignore horizontal gestures"
    )

    try expectClose(
        HoverVolumeLogic.volumeDelta(
            scrollingDeltaX: 8,
            scrollingDeltaY: 2,
            hasPreciseScrollingDeltas: true,
            momentumPhaseIsEmpty: true,
            axisPreference: .anyDirection
        ),
        0.032,
        "Any-direction scrolling should use the dominant axis"
    )

    try expectEqual(
        HoverVolumeLogic.speakerSymbolName(for: 0),
        "speaker.slash.fill",
        "Muted volume should show the slash icon"
    )

    try expectEqual(
        HoverVolumeLogic.speakerSymbolName(for: 0.2),
        "speaker.fill",
        "Low volume should show the single speaker icon"
    )

    try expectEqual(
        HoverVolumeLogic.speakerSymbolName(for: 0.5),
        "speaker.wave.2.fill",
        "Mid volume should show the medium wave icon"
    )

    try expectEqual(
        HoverVolumeLogic.speakerSymbolName(for: 0.9),
        "speaker.wave.3.fill",
        "High volume should show the full wave icon"
    )

    try expectEqual(
        HoverVolumeLogic.normalizedVersionString("v1.2.3"),
        "1.2.3",
        "Version normalization should drop a leading v prefix"
    )

    try expect(
        HoverVolumeLogic.isVersion("v1.2.0", newerThan: "1.1.9"),
        "A higher GitHub tag should be considered newer than the current app version"
    )

    try expect(
        !HoverVolumeLogic.isVersion("1.1.0", newerThan: "1.1.0"),
        "Equal versions should not be considered updates"
    )

    try expect(
        !HoverVolumeLogic.isVersion("1.0.9", newerThan: "1.1.0"),
        "Older versions should not be considered updates"
    )
}

@main
struct TestRunner {
    static func main() {
        do {
            try runTests()
            print("HoverVolumeLogic tests passed")
        } catch {
            fputs("Test failure: \(error)\n", stderr)
            exit(1)
        }
    }
}
