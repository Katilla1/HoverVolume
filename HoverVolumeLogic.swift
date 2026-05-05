enum HoverVolumeLogic {
    static let wheelStep: Float32 = 0.05
    static let trackpadDeltaScale: Float32 = 0.004
    static let maxTrackpadDeltaPerEvent: Float32 = 0.08

    static func volumeDelta(
        scrollingDeltaX: Double,
        scrollingDeltaY: Double,
        hasPreciseScrollingDeltas: Bool,
        momentumPhaseIsEmpty: Bool
    ) -> Float32? {
        guard momentumPhaseIsEmpty else { return nil }

        let dominantDelta = dominantScrollDelta(
            scrollingDeltaX: scrollingDeltaX,
            scrollingDeltaY: scrollingDeltaY
        )
        guard abs(dominantDelta) >= 0.01 else { return nil }

        if hasPreciseScrollingDeltas {
            let scaled = Float32(dominantDelta) * trackpadDeltaScale
            return max(-maxTrackpadDeltaPerEvent, min(maxTrackpadDeltaPerEvent, scaled))
        }

        return dominantDelta > 0 ? wheelStep : -wheelStep
    }

    private static func dominantScrollDelta(
        scrollingDeltaX: Double,
        scrollingDeltaY: Double
    ) -> Double {
        abs(scrollingDeltaX) > abs(scrollingDeltaY) ? scrollingDeltaX : scrollingDeltaY
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
}
