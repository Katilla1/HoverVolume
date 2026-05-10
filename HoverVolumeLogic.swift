import Foundation

enum ScrollAxisPreference: String, CaseIterable {
    case verticalOnly
    case verticalPriority
    case anyDirection
}

enum HoverVolumeLogic {
    static let wheelStep: Float32 = 0.05
    static let trackpadDeltaScale: Float32 = 0.004
    static let maxTrackpadDeltaPerEvent: Float32 = 0.08
    static let minimumScrollDelta = 0.01

    static func volumeDelta(
        scrollingDeltaX: Double,
        scrollingDeltaY: Double,
        hasPreciseScrollingDeltas: Bool,
        momentumPhaseIsEmpty: Bool,
        axisPreference: ScrollAxisPreference = .verticalPriority
    ) -> Float32? {
        guard momentumPhaseIsEmpty else { return nil }

        guard let activeDelta = preferredScrollDelta(
            scrollingDeltaX: scrollingDeltaX,
            scrollingDeltaY: scrollingDeltaY,
            axisPreference: axisPreference
        ) else {
            return nil
        }

        if hasPreciseScrollingDeltas {
            let scaled = Float32(activeDelta) * trackpadDeltaScale
            return max(-maxTrackpadDeltaPerEvent, min(maxTrackpadDeltaPerEvent, scaled))
        }

        return activeDelta > 0 ? wheelStep : -wheelStep
    }

    private static func preferredScrollDelta(
        scrollingDeltaX: Double,
        scrollingDeltaY: Double,
        axisPreference: ScrollAxisPreference
    ) -> Double? {
        switch axisPreference {
        case .verticalOnly:
            return abs(scrollingDeltaY) >= minimumScrollDelta ? scrollingDeltaY : nil
        case .verticalPriority:
            if abs(scrollingDeltaY) >= minimumScrollDelta {
                return scrollingDeltaY
            }

            return abs(scrollingDeltaX) >= minimumScrollDelta ? scrollingDeltaX : nil
        case .anyDirection:
            let dominantDelta = abs(scrollingDeltaX) > abs(scrollingDeltaY) ? scrollingDeltaX : scrollingDeltaY
            return abs(dominantDelta) >= minimumScrollDelta ? dominantDelta : nil
        }
    }

    static func speakerSymbolName(for volume: Double) -> String {
        switch volume {
        case ...0:
            return "speaker.slash.fill"
        case ..<0.34:
            return "speaker.fill"
        case ..<0.67:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }

    static func normalizedVersionString(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }

        return trimmed
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let normalizedCandidate = normalizedVersionString(candidate)
        let normalizedCurrent = normalizedVersionString(current)

        guard !normalizedCandidate.isEmpty, !normalizedCurrent.isEmpty else { return false }
        guard normalizedCandidate != normalizedCurrent else { return false }

        return normalizedCandidate.compare(normalizedCurrent, options: .numeric) == .orderedDescending
    }
}
