import Foundation

/// Auto-scroll as a flywheel with friction: speaking spins it up toward
/// your average pace, stopping lets it coast down, and a weak spring
/// nudges the current line toward the middle. Velocity is state and only
/// acceleration changes, so pace updates and line changes never jolt it.
struct Flywheel {
  var position: Double = 0
  var velocity: Double = 0
  /// Averaged speaking speed, points/second.
  private(set) var pace: Double = 0

  var paceAveraging: Double = 4      // s
  var spinUp: Double = 0.8           // s, approach to pace while speaking
  var coastFriction: Double = 0.9    // 1/s when the speaker stops
  var spring: Double = 0.5           // 1/s², toward centering the line
  var aheadBrake: Double = 1.5       // 1/s, when past the speaker
  var maxAcceleration: Double = 300  // pt/s²

  /// - Parameters:
  ///   - target: offset that centers the speaker's current line.
  ///   - speakingPace: current speaking speed in points/second.
  ///   - speaking: whether the speaker advanced recently.
  mutating func step(dt: Double, target: Double, speakingPace: Double, speaking: Bool) {
    guard dt > 0 else { return }
    if speaking, speakingPace > 0 {
      pace += (speakingPace - pace) * min(1, dt / paceAveraging)
    }
    let error = target - position
    var a = spring * error
    if speaking {
      a += (pace - velocity) / spinUp
    } else {
      a -= coastFriction * velocity
    }
    if error < 0 { a -= aheadBrake * velocity }
    a = min(max(a, -maxAcceleration), maxAcceleration)
    velocity = max(0, velocity + a * dt)
    position += velocity * dt
  }

  /// Re-sync after the user scrolls by hand.
  mutating func reset(position: Double) {
    self.position = position
    velocity = 0
  }
}
