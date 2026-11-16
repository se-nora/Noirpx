// CraftingGating.swift
// Pure gating logic for spell crafting UI — safe-zone only (Noita Holy Mountain pattern)

import Foundation
import SimulationCore

public enum CraftingGating {
    /// Returns true when the crafting UI may be shown/toggled.
    /// Allows crafting only when a run exists and has ended (any outcome != .playing).
    /// This covers .fell today and future terminal states (.won, .exhausted) without requiring updates.
    /// Returns false when there is no run (nil) or the run is still .playing.
    public static func isAllowed(_ outcome: CaveRun.Outcome?) -> Bool {
        outcome != nil && outcome != .playing
    }
}