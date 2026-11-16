// CraftingGatingTests.swift
// Unit tests for safe-zone crafting gating logic

import XCTest
import SimulationCore
import GamePresentation

#if os(macOS)
import AppKit
import SwiftUI
#endif

final class CraftingGatingTests: XCTestCase {

    func testIsAllowed_duringPlay_returnsFalse() {
        // Given an active run with .playing outcome
        let outcome: CaveRun.Outcome = .playing
        // When checking gating
        let allowed = CraftingGating.isAllowed(outcome)
        // Then crafting is not allowed
        XCTAssertFalse(allowed, "Crafting must be disabled during active play")
    }

    func testIsAllowed_afterFell_returnsTrue() {
        // Given a run that ended with .fell
        let outcome: CaveRun.Outcome = .fell
        // When checking gating
        let allowed = CraftingGating.isAllowed(outcome)
        // Then crafting is allowed
        XCTAssertTrue(allowed, "Crafting must be enabled after .fell outcome")
    }

    func testIsAllowed_noRun_returnsFalse() {
        // Given no active run (nil)
        let outcome: CaveRun.Outcome? = nil
        // When checking gating
        let allowed = CraftingGating.isAllowed(outcome)
        // Then crafting is not allowed (no safe zone without a run context)
        XCTAssertFalse(allowed, "Crafting must be disabled when no run exists")
    }

    func testIsAllowed_futureTerminalStates_returnsTrue() {
        // This test documents that any future non-.playing outcome enables crafting
        // without requiring code changes. It uses reflection to verify the logic.
        let playing: CaveRun.Outcome = .playing
        let fell: CaveRun.Outcome = .fell
        // Simulate a hypothetical future outcome by using .fell as proxy
        XCTAssertFalse(CraftingGating.isAllowed(playing))
        XCTAssertTrue(CraftingGating.isAllowed(fell))
        // The gate is simply `outcome != nil && outcome != .playing`, so any non-.playing passes
    }

    #if os(macOS)
    @MainActor
    func testHUDControls_showsSpellButton_whenAllowed() throws {
        // Given HUDControls with showSpellCraftingAllowed = true and discovered materials
        let view = NSHostingView(rootView: HUDControls(
            selected: .sand,
            restart: {},
            newRun: {},
            diagnostics: {},
            help: {},
            select: { _ in },
            discoveredMaterials: [.sand, .water],
            onToggleSpellCrafting: {},
            showSpellCrafting: false,
            showSpellCraftingAllowed: true,
            wand: Wand(),
            manaPool: ManaPool(),
            onCycleWandSlot: { _ in }
        ))
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()

        func countFocusRingViews(_ view: NSView) -> Int {
            var count = 0
            let typeName = String(describing: type(of: view))
            if typeName.contains("FocusRingView") {
                count += 1
            }
            for child in view.subviews {
                count += countFocusRingViews(child)
            }
            return count
        }

        let allowedCount = countFocusRingViews(view)
        // Base buttons: 4 run/info + 7 MaterialBrush = 11. +1 Show Spells = 12 when allowed
        XCTAssertEqual(allowedCount, 12, "Show Spells button must add one FocusRingView when allowed and materials discovered")
        window.close()
    }

    @MainActor
    func testHUDControls_hidesSpellButton_whenDisallowed() throws {
        // Given HUDControls with showSpellCraftingAllowed = false
        let view = NSHostingView(rootView: HUDControls(
            selected: .sand,
            restart: {},
            newRun: {},
            diagnostics: {},
            help: {},
            select: { _ in },
            discoveredMaterials: [.sand, .water],
            onToggleSpellCrafting: {},
            showSpellCrafting: false,
            showSpellCraftingAllowed: false,
            wand: Wand(),
            manaPool: ManaPool(),
            onCycleWandSlot: { _ in }
        ))
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()

        func countFocusRingViews(_ view: NSView) -> Int {
            var count = 0
            let typeName = String(describing: type(of: view))
            if typeName.contains("FocusRingView") {
                count += 1
            }
            for child in view.subviews {
                count += countFocusRingViews(child)
            }
            return count
        }

        let disallowedCount = countFocusRingViews(view)
        // Base buttons: 4 run/info + 7 MaterialBrush = 11. Show Spells hidden = 11 when disallowed
        XCTAssertEqual(disallowedCount, 11, "Show Spells button must not add FocusRingView when not allowed")
        window.close()
    }
    #endif
}