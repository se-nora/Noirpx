import XCTest
import SimulationCore

final class ManaPoolTests: XCTestCase {

    func testManaPoolInitialization() {
        let pool = ManaPool()
        XCTAssertEqual(pool.current, 100)
        XCTAssertEqual(pool.maximum, 255)
        XCTAssertEqual(pool.regenerationPerTick, 1)
    }

    func testManaPoolCustomStartingMana() {
        let pool = ManaPool(startingMana: 50)
        XCTAssertEqual(pool.current, 50)

        // Starting mana capped at maximum (UInt8 max is 255)
        let cappedPool = ManaPool(startingMana: 255)
        XCTAssertEqual(cappedPool.current, 255)
    }

    func testManaPoolSpendSuccess() {
        var pool = ManaPool(startingMana: 100)
        let result = pool.spend(30)
        XCTAssertTrue(result)
        XCTAssertEqual(pool.current, 70)
    }

    func testManaPoolSpendInsufficientMana() {
        var pool = ManaPool(startingMana: 50)
        let result = pool.spend(75)
        XCTAssertFalse(result)
        XCTAssertEqual(pool.current, 50) // Unchanged
    }

    func testManaPoolSpendExactAmount() {
        var pool = ManaPool(startingMana: 100)
        let result = pool.spend(100)
        XCTAssertTrue(result)
        XCTAssertEqual(pool.current, 0)
    }

    func testManaPoolSpendZero() {
        var pool = ManaPool(startingMana: 100)
        let result = pool.spend(0)
        XCTAssertTrue(result)
        XCTAssertEqual(pool.current, 100)
    }

    func testManaPoolRefund() {
        var pool = ManaPool(startingMana: 100)
        _ = pool.spend(40)
        XCTAssertEqual(pool.current, 60)

        pool.refund(30)
        XCTAssertEqual(pool.current, 90)
    }

    func testManaPoolRefundCapsAtMaximum() {
        var pool = ManaPool(startingMana: 200)
        _ = pool.spend(10)
        XCTAssertEqual(pool.current, 190)

        pool.refund(100) // Would exceed max
        XCTAssertEqual(pool.current, 255)
    }

    func testManaPoolRefundZero() {
        var pool = ManaPool(startingMana: 100)
        pool.refund(0)
        XCTAssertEqual(pool.current, 100)
    }

    func testManaPoolRegenerate() {
        var pool = ManaPool(startingMana: 100)
        pool.regenerate()
        XCTAssertEqual(pool.current, 101)
    }

    func testManaPoolRegenerateCapsAtMaximum() {
        var pool = ManaPool(startingMana: 255)
        pool.regenerate()
        XCTAssertEqual(pool.current, 255)

        // Spend 1, then regenerate to cap
        _ = pool.spend(1)
        XCTAssertEqual(pool.current, 254)
        pool.regenerate()
        XCTAssertEqual(pool.current, 255)
    }

    func testManaPoolCanAfford() {
        let pool = ManaPool(startingMana: 100)
        XCTAssertTrue(pool.canAfford(0))
        XCTAssertTrue(pool.canAfford(50))
        XCTAssertTrue(pool.canAfford(100))
        XCTAssertFalse(pool.canAfford(101))
        XCTAssertFalse(pool.canAfford(255))
    }

    func testManaPoolEquality() {
        let pool1 = ManaPool(startingMana: 100)
        let pool2 = ManaPool(startingMana: 100)
        let pool3 = ManaPool(startingMana: 50)

        XCTAssertEqual(pool1, pool2)
        XCTAssertNotEqual(pool1, pool3)
    }

    func testManaPoolSendable() {
        // Verify ManaPool is Sendable by using it across a task boundary
        let pool = ManaPool(startingMana: 100)
        Task {
            _ = pool.canAfford(50)
            XCTAssertEqual(pool.current, 100)
        }
    }

    func testManaPoolUnderflowProtection() {
        var pool = ManaPool(startingMana: 10)
        _ = pool.spend(10)
        XCTAssertEqual(pool.current, 0)

        // Further spend should fail, not underflow
        let result = pool.spend(1)
        XCTAssertFalse(result)
        XCTAssertEqual(pool.current, 0)
    }

    func testManaPoolOverflowProtection() {
        var pool = ManaPool(startingMana: 250)
        pool.refund(10)
        XCTAssertEqual(pool.current, 255)

        pool.regenerate()
        XCTAssertEqual(pool.current, 255)
    }

    func testManaPoolSpendAndRegenerateSequence() {
        var pool = ManaPool(startingMana: 100)

        _ = pool.spend(30)
        XCTAssertEqual(pool.current, 70)

        pool.regenerate()
        XCTAssertEqual(pool.current, 71)

        _ = pool.spend(20)
        XCTAssertEqual(pool.current, 51)

        pool.refund(10)
        XCTAssertEqual(pool.current, 61)
    }

    func testManaPoolMultipleSpends() {
        var pool = ManaPool(startingMana: 100)

        XCTAssertTrue(pool.spend(25))
        XCTAssertTrue(pool.spend(25))
        XCTAssertTrue(pool.spend(25))
        XCTAssertTrue(pool.spend(25))
        XCTAssertEqual(pool.current, 0)

        // Next spend fails
        XCTAssertFalse(pool.spend(1))
        XCTAssertEqual(pool.current, 0)
    }
}