import SimulationCore

/// Short, presentation-only guidance for the current run.
public enum HUDGuideText {
    public static func objective(outcome: BeaconRun.Outcome?, collected: Int) -> String {
        guard let outcome else { return "Waiting for run" }
        switch outcome {
        case .playing:
            return collected >= 2 ? "Both found: touch green gate" : "Touch 2 amber beacons, then gate"
        case .won:
            return "Run complete • Restart or New Run"
        case .fell, .exhausted:
            return "Run ended • Restart to retry"
        }
    }

    public enum Controls {
        case keyboard, touch
    }

    public static func controls(_ controls: Controls) -> [String] {
        switch controls {
        case .keyboard: return ["A/D move • Space jump", "F pulse • drag paints"]
        case .touch: return ["←/→ move • ↑ jump", "⚡ pulse • drag paints"]
        }
    }

    /// Status of the Chime Warden, including its material damage state.
    public static func warden(_ warden: ChimeWarden?) -> String {
        guard let warden else { return "Warden none" }
        guard warden.alive else { return "Warden down" }
        var text = "Warden shield \(warden.shield)/\(ChimeWarden.maximumShield)"
        if warden.burning { text += " • burning" }
        if let hazard = warden.lastHazard { text += " • hit by \(hazard.rawValue)" }
        return text
    }
}

#if canImport(SwiftUI)
import SwiftUI

public struct HUDGuide: View {
    private let outcome: BeaconRun.Outcome?
    private let collected: Int
    private let controls: HUDGuideText.Controls

    public init(outcome: BeaconRun.Outcome?, collected: Int, controls: HUDGuideText.Controls) {
        self.outcome = outcome
        self.collected = collected
        self.controls = controls
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(HUDGuideText.objective(outcome: outcome, collected: collected))
            ForEach(HUDGuideText.controls(controls), id: \.self) { Text($0) }
            Text("Black/white marks: burning contact")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
