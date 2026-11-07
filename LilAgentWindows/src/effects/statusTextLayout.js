export const STATUS_PHRASES = {
  boot: 'Hello there!', idle: 'Just hanging out.', walk: 'Just stretching my legs.',
  happy: 'Life is good.', excited: 'Ooh, let’s go!', curious: 'What’s that?',
  sad: 'A little blue today.', coffee: 'Tiny coffee break.', workout: 'One more rep!',
  meditate: 'Finding my zen.', idea: 'Oh! I’ve got it!', dance: 'This is my song!',
  wave: 'Hey, you!', annoyed: 'Okay, okay…', grumpy: 'Okay, okay…', dizzy: 'Everything’s spinning…',
  sleepy: 'Getting sleepy…', sleep: 'Zzz…', wake: 'Five more minutes…',
  thinking: 'Hmm…', reading: 'Taking a look.', searching: 'Looking for clues.',
  typing: 'Typing something…', command: 'Running a command…', planning: 'Putting a plan together.',
  subagents: 'Calling in some help!', permission: 'Can I do this?', question: 'Quick question…',
  attention: 'Need your attention.', compacting: 'Compacting', error: 'Oops. Hit a snag.',
  done: 'All done!', donehold: 'All done!', waiting: 'Ready when you are.',
  pet: 'That’s the spot.', carried: 'Where are we going?', drop: 'Whoa!', settle: 'Found my spot.',
  surprised: 'Oh!',
};

export function statusTextExtent(x, facing, scale, halfWidth, halfDepth, cameraDistance) {
  const c = Math.cos(facing), s = Math.sin(facing);
  let extent = 0;
  for (const dx of [-halfWidth, halfWidth]) {
    for (const dz of [-halfDepth, halfDepth]) {
      const px = (c * dx + s * dz) * scale, pz = (-s * dx + c * dz) * scale;
      extent = Math.max(extent, Math.abs((x + px) * cameraDistance / Math.max(0.001, cameraDistance - pz) - x));
    }
  }
  return extent;
}

export function statusTextLayout({ x, y, extent, width, height, halfWidth, halfHeight, side }) {
  const margin = 0.08, gap = 0.12;
  const right = Math.max(0, halfWidth - margin - (x + extent + gap));
  const left = Math.max(0, x - extent - gap + halfWidth - margin);
  const wanted = side > 0 ? right : left, other = side > 0 ? left : right;
  if (wanted < width && other > wanted + 0.01) side *= -1;
  const available = side > 0 ? right : left;
  const scale = Math.min(1, available / Math.max(width, 0.001), Math.max(0, 2 * (halfHeight - margin)) / Math.max(height, 0.001));
  const h = height * scale;
  return {
    x: x + side * (extent + gap + width * scale / 2),
    y: Math.max(-halfHeight + margin + h / 2, Math.min(halfHeight - margin - h / 2, y)),
    scale, side,
  };
}

export function avoidStatusProps(layout, { width, height, halfWidth, halfHeight, obstacles, attachBelow = false }) {
  const gap = attachBelow ? 0.025 : 0.12, margin = 0.08;
  const w = width * layout.scale, h = height * layout.scale;
  const horizontal = obstacles.filter((b) => layout.x + w / 2 + gap > b.minX && layout.x - w / 2 - gap < b.maxX);
  let y = layout.y;
  if (attachBelow && horizontal.length) y = Math.min(halfHeight - margin - h / 2, Math.min(...horizontal.map((b) => b.minY)) - gap - h / 2);
  for (let i = 0; i < horizontal.length; i++) {
    for (const b of horizontal) {
      if (y + h / 2 + gap > b.minY && y - h / 2 - gap < b.maxY) y = Math.min(y, b.minY - gap - h / 2);
    }
  }
  const bottom = -halfHeight + margin;
  if (y - h / 2 >= bottom) return { ...layout, y };
  const outerEdge = layout.side > 0 ? Math.max(...obstacles.map((b) => b.maxX)) : Math.min(...obstacles.map((b) => b.minX));
  const outerX = outerEdge + layout.side * (gap + w / 2);
  if (Math.abs(outerX) + w / 2 <= halfWidth - margin) return { ...layout, x: outerX };
  const available = Math.max(0, y + h / 2 - bottom);
  const scale = Math.min(layout.scale, available / height);
  return { ...layout, scale, y: bottom + height * scale / 2 };
}
