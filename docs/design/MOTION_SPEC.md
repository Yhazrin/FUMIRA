# Motion Specification

## Tokens from Figma

| Token | Duration | Intent |
|---|---:|---|
| Micro | 180ms | press, snap-like feedback, micro response |
| Time Flow | 340ms | soft rail/scene reveal |
| Poster | 420ms | segmented display lettering entrance |
| Page | 520ms | lens/photo continuous transformation |
| Reduced | 150ms | opacity crossfade only |

## Rules

- Press compresses first; release overshoots slightly and settles.
- The lens, scene, and time seed persist across major phase transitions.
- When the shutter moves, poster text stays stable.
- While time changes, animate only scene treatment, active rail, and numeric label.
- Scrubbing is interruptible. Never queue animations for prior time values.
- In Reduce Motion, disable parallax, rotation, scale, orbit, and geometry travel.
- Haptic feedback is sparse: NOW crossing and decade crossings, not every drag tick.

## Continuous rail

The thumb directly follows touch. A separate presentation value may spring toward
the domain value after release, but it may not snap to landmarks. Landmarks at
-100, -30, NOW, +30, +100 are labels only.
