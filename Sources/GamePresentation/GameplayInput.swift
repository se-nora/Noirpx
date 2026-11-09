/// Device-independent input aggregation; one-shot presses survive until a simulation tick.
public enum GameplayControl {
    case left, right, jump, pulse
}

public struct GameplayControls {
    public var left = false
    public var right = false
    public var jump = false
    public var pulse = false

    public init(left: Bool = false, right: Bool = false, jump: Bool = false, pulse: Bool = false) {
        self.left = left
        self.right = right
        self.jump = jump
        self.pulse = pulse
    }
}

public struct GameplayInput {
    private var keyboard = GameplayControls()
    private var touch = GameplayControls()
    private var pendingJump = false
    private var pendingPulse = false
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
        case .pulse: controls.pulse = pressed
        }
        update(keyboard: keyboard, touch: controls)
    }

    public mutating func activate(_ control: GameplayControl) {
        switch control {
        case .left: accessibilityHorizontal = -1
        case .right: accessibilityHorizontal = 1
        case .jump: pendingJump = true
        case .pulse: pendingPulse = true
        }
    }

    public mutating func consumeTick() -> (horizontal: Int, jump: Bool, pulse: Bool) {
        let held = (keyboard.right || touch.right ? 1 : 0) - (keyboard.left || touch.left ? 1 : 0)
        let result = (held == 0 ? accessibilityHorizontal : held, pendingJump,
                      pendingPulse || keyboard.pulse || touch.pulse)
        pendingJump = false
        pendingPulse = false
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
        if !(self.keyboard.pulse || self.touch.pulse) && (keyboard.pulse || touch.pulse) {
            pendingPulse = true
        }
        self.keyboard = keyboard
        self.touch = touch
    }
}
