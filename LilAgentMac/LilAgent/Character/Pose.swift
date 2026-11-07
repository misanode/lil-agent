enum PoseKey: Int, CaseIterable {
    case bodyY, crouch, sit
    case torsoPitch, torsoYaw, torsoRoll
    case headYaw, headPitch, headRoll
    case armRaiseL, armRaiseR, armSwingL, armSwingR, armTwistL, armTwistR
    case elbowL, elbowR, wristL, wristR
    case legSwingL, legSwingR, kneeL, kneeR, legSpreadL, legSpreadR

    static func armRaise(_ side: String) -> PoseKey { side == "L" ? .armRaiseL : .armRaiseR }
    static func elbow(_ side: String) -> PoseKey { side == "L" ? .elbowL : .elbowR }
    static func armSwing(_ side: String) -> PoseKey { side == "L" ? .armSwingL : .armSwingR }
    static func wrist(_ side: String) -> PoseKey { side == "L" ? .wristL : .wristR }
}

struct Pose {
    var v = [Double](repeating: 0, count: PoseKey.allCases.count)

    subscript(_ k: PoseKey) -> Double {
        get { v[k.rawValue] }
        set { v[k.rawValue] = newValue }
    }

    mutating func reset() {
        for i in v.indices { v[i] = 0 }
    }

    mutating func damp(toward target: Pose, rate: Double, dt: Double) {
        let a = 1 - Foundation.exp(-rate * dt)
        for i in v.indices { v[i] += (target.v[i] - v[i]) * a }
    }
}

import Foundation
