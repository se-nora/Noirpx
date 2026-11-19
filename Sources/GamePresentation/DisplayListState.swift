import Foundation
import SimulationCore

/// World kind for HUD layout.
public enum DisplayWorldKind: Equatable, Sendable {
    case cave
    case beacon
}

/// Run outcome for HUD status line.
public enum DisplayOutcome: Equatable, Sendable {
    case playing
    case won
    case fell
    case exhausted
    case died
}

/// Warden state for beacon HUD.
public struct DisplayWarden: Equatable, Sendable {
    public let alive: Bool
    public let shield: Int
    public let burning: Bool
    public let lastHazardName: String?

    public init(alive: Bool, shield: Int, burning: Bool, lastHazardName: String?) {
        self.alive = alive
        self.shield = shield
        self.burning = burning
        self.lastHazardName = lastHazardName
    }
}

/// Control scheme for help overlay.
public enum DisplayControlScheme: Equatable, Sendable {
    case keyboard
    case touch
}

/// Overlay visibility flags.
public struct DisplayOverlayVisibility: Equatable, Sendable {
    public let stats: Bool
    public let help: Bool
    public let crafting: Bool

    public init(stats: Bool, help: Bool, crafting: Bool) {
        self.stats = stats
        self.help = help
        self.crafting = crafting
    }
}

/// Complete input state for building a display list. Plain value type, no platform deps.
public struct DisplayListState: Equatable, Sendable {
    // Version / identity
    public let version: String
    public let worldKind: DisplayWorldKind
    public let seed: UInt64
    public let worldWidth: Int
    public let worldHeight: Int

    // Character / run state
    public let position: CellPosition?
    public let tick: UInt64
    public let depth: Int?
    public let outcome: DisplayOutcome?

    // Cave HUD
    public let health: Int?
    public let maxHealth: Int?
    public let energy: Int?
    public let maxEnergy: Int?

    // Beacon HUD
    public let collectedBeacons: Int
    public let warden: DisplayWarden?

    // Brush / wand
    public let selectedMaterial: Material
    public let isCasting: Bool
    public let discoveredMaterials: Set<Material>
    public let wand: Wand
    public let manaPool: ManaPool

    // Crafting
    public let showCraftingGrid: Bool
    public let craftingAllowed: Bool
    public let craftingGrid: CraftingGrid

    // Diagnostics
    public let framesPerSecond: Double?
    public let renderedChunks: Int?
    public let errorMessage: String?

    // Status
    public let hoveredMaterialName: String?
    public let hudVisible: Bool
    public let controls: DisplayControlScheme
    public let overlays: DisplayOverlayVisibility

    public init(
        version: String,
        worldKind: DisplayWorldKind,
        seed: UInt64,
        worldWidth: Int,
        worldHeight: Int,
        position: CellPosition? = nil,
        tick: UInt64,
        depth: Int? = nil,
        outcome: DisplayOutcome? = nil,
        health: Int? = nil,
        maxHealth: Int? = nil,
        energy: Int? = nil,
        maxEnergy: Int? = nil,
        collectedBeacons: Int = 0,
        warden: DisplayWarden? = nil,
        selectedMaterial: Material,
        isCasting: Bool,
        discoveredMaterials: Set<Material> = [],
        wand: Wand = Wand(),
        manaPool: ManaPool = ManaPool(),
        showCraftingGrid: Bool = false,
        craftingAllowed: Bool = false,
        craftingGrid: CraftingGrid = CraftingGrid(),
        framesPerSecond: Double? = nil,
        renderedChunks: Int? = nil,
        errorMessage: String? = nil,
        hoveredMaterialName: String? = nil,
        hudVisible: Bool = true,
        controls: DisplayControlScheme = .keyboard,
        overlays: DisplayOverlayVisibility = DisplayOverlayVisibility(stats: false, help: false, crafting: false)
    ) {
        self.version = version
        self.worldKind = worldKind
        self.seed = seed
        self.worldWidth = worldWidth
        self.worldHeight = worldHeight
        self.position = position
        self.tick = tick
        self.depth = depth
        self.outcome = outcome
        self.health = health
        self.maxHealth = maxHealth
        self.energy = energy
        self.maxEnergy = maxEnergy
        self.collectedBeacons = collectedBeacons
        self.warden = warden
        self.selectedMaterial = selectedMaterial
        self.isCasting = isCasting
        self.discoveredMaterials = discoveredMaterials
        self.wand = wand
        self.manaPool = manaPool
        self.showCraftingGrid = showCraftingGrid
        self.craftingAllowed = craftingAllowed
        self.craftingGrid = craftingGrid
        self.framesPerSecond = framesPerSecond
        self.renderedChunks = renderedChunks
        self.errorMessage = errorMessage
        self.hoveredMaterialName = hoveredMaterialName
        self.hudVisible = hudVisible
        self.controls = controls
        self.overlays = overlays
    }
}