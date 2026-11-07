export const POSE_KEYS = [
  'bodyY', 'crouch', 'sit',
  'torsoPitch', 'torsoYaw', 'torsoRoll',
  'headYaw', 'headPitch', 'headRoll',
  'armRaiseL', 'armRaiseR', 'armSwingL', 'armSwingR', 'armTwistL', 'armTwistR',
  'elbowL', 'elbowR', 'wristL', 'wristR',
  'legSwingL', 'legSwingR', 'kneeL', 'kneeR', 'legSpreadL', 'legSpreadR',
];

export const armRaise = (side) => (side === 'L' ? 'armRaiseL' : 'armRaiseR');
export const elbow = (side) => (side === 'L' ? 'elbowL' : 'elbowR');
export const armSwing = (side) => (side === 'L' ? 'armSwingL' : 'armSwingR');
export const wrist = (side) => (side === 'L' ? 'wristL' : 'wristR');

export class Pose {
  constructor() { this.reset(); }

  reset() {
    for (const k of POSE_KEYS) this[k] = 0;
  }

  dampToward(target, rate, dt) {
    const a = 1 - Math.exp(-rate * dt);
    for (const k of POSE_KEYS) this[k] += (target[k] - this[k]) * a;
  }

  copyFrom(other) {
    for (const k of POSE_KEYS) this[k] = other[k];
  }
}
