import XCTest
@testable import SimulationCore
import Foundation

final class DebugInit2: XCTestCase {
    func testInit() throws {
        var run = try CaveRun(seed: 1, width: 256, height: 128)
        fputs("DEBUG: spawn=\(run.world.spawn) goal=\(run.world.goal) charPos=\(run.character.position) charGrounded=\(run.character.grounded)\n", stderr)
        
        // Check material below character
        for dx in 0..<FixtureCharacter.width {
            let checkPos = CellPosition(x: run.character.position.x + dx, y: run.character.position.y - 1)
            if let mat = try? run.world.material(at: checkPos) {
                fputs("  Ground check at \(checkPos): \(mat) blocks=\(mat.blocksCharacter)\n", stderr)
            }
        }
    }
}
