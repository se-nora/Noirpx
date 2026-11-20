/// Gravity factor in Q8 format (UInt16). 0 = no gravity, 256 = 1.0 gravity per tick².
/// Stored as UInt16 to match spec; max value 65535 ≈ 255.99 gravity.
public typealias GravityFactor = UInt16