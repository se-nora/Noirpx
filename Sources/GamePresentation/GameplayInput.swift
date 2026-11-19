/// Device-independent input aggregation; one-shot presses survive until a simulation tick.
public enum GameplayControl {
    case left, right, jump
}

public struct GameplayControls: Equatable {
    public var left = false
    public var right = false
    public var jump = false

    public init(left: Bool = false, right: Bool = false, jump: Bool = false) {
        self.left = left
        self.right = right
        self.jump = jump
    }
}

public struct GameplayInputResult: Equatable {
    public var horizontal: Int
    public var jump: Bool
    /// Held jump state (current frame): true while the jump key/button is held down.
    public var heldJump: Bool

    public init(horizontal: Int, jump: Bool, heldJump: Bool = false) {
        self.horizontal = horizontal
        self.jump = jump
        self.heldJump = heldJump
    }
}

public struct GameplayInput {
    private var keyboard = GameplayControls()
    private var touch = GameplayControls()
    private var pendingJump = false
    private var accessibilityHorizontal = 0

    public init() {}

    public mutating func setKeyboard(_ controls: GameplayControls) {
        update(keyboard: controls, touch: touch)
    }

    public mutating func setTouch(_ control: GameplayControl, pressed: Bool) {
        var controls = touch
        switch control {
        case .left: controls.left = pressed
        case .right: controls.right = pressed
        case .jump: controls.jump = pressed
        }
        update(keyboard: keyboard, touch: controls)
    }

    public mutating func activate(_ control: GameplayControl) {
        switch control {
        case .left: accessibilityHorizontal = -1
        case .right: accessibilityHorizontal = 1
        case .jump: pendingJump = true
        }
    }

    public mutating func consumeTick() -> GameplayInputResult {
        let held = (keyboard.right || touch.right ? 1 : 0) - (keyboard.left || touch.left ? 1 : 0)
        let heldJump = keyboard.jump || touch.jump
        let result = GameplayInputResult(horizontal: held == 0 ? accessibilityHorizontal : held,
                                         jump: pendingJump,
                                         heldJump: heldJump)
        pendingJump = false
        accessibilityHorizontal = 0
        return result
    }

    public mutating func reset() {
        self = GameplayInput()
    }

    private mutating func update(keyboard: GameplayControls, touch: GameplayControls) {
        if !(self.keyboard.jump || self.touch.jump) && (keyboard.jump || touch.jump) {
            pendingJump = true
        }
        self.keyboard = keyboard
        self.touch = touch
    }
}