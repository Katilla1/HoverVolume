enum HoverVolumeLogic {
    static let wheelStep: Float32 = 0.05
    static let trackpadDeltaScale: Float32 = 0.004
    static let maxTrackpadDeltaPerEvent: Float32 = 0.08

    static func volumeDelta(
        scrollingDeltaY: Double,
        hasPreciseScrollingDeltas: Bool,
        momentumPhaseIsEmpty: Bool
    ) -> Float32? {
        guard abs(scrollingDeltaY) >= 0.01 else { return nil }
        guard momentumPhaseIsEmpty else { return nil }

        if hasPreciseScrollingDeltas {
            let scaled = Float32(scrollingDeltaY) * trackpadDeltaScale
            return max(-maxTrackpadDeltaPerEvent, min(maxTrackpadDeltaPerEvent, scaled))
        }

        return scrollingDeltaY > 0 ? wheelStep : -wheelStep
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
