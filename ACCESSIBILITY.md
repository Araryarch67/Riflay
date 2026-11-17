# Accessibility

Riflay should be usable by everyone who wants to listen to music. This page says what it supports today, what is
known not to work well yet, and how to tell us about a barrier.

## What Riflay supports

- **Screen readers**: controls have labels and tooltips (TalkBack, VoiceOver, Narrator, Orca through Flutter's
  semantics).
- **Keyboard**: play/pause, next/previous, seeking, volume and search work from the keyboard on computers; the mini
  player has its own shortcuts (Space, Ctrl+←/→, Esc).
- **Text size**: Settings › Look & feel › Text, and the system's own text scale.
- **Contrast**: a High contrast option and several themes (light and dark) in Settings › Look & feel › Appearance.
- **Reduced motion**: Settings › Pages & navigation › Motion, and the system's "reduce motion" switch turns off
  animations, the visualizer and moving decorations.
- **Lightweight mode**: no blur or effects, for slower devices and people who find motion or transparency distracting.
- **Lyrics**: larger lyrics, alignment, dimmed unsung lines, and the line being sung on the lock screen.

## Supported environments

Windows 10/11, macOS, Linux (X11 and Wayland), Android and iOS, each with its own screen reader.

## Known limitations

- Some custom controls (the wavy seek bar, the visualizer, the island's animations) are decorative and may read
  less clearly than standard controls.
- The music video and lyrics pages are visual first; captions come from the lyrics, not from the video.
- Translations are English, Indonesian and Japanese; other languages fall back to English.

## Reporting a barrier

Open an [issue](https://github.com/Araryarch67/Riflay/issues/new) and say:

- what you were trying to do,
- your platform, Riflay version and assistive technology (screen reader, magnifier, keyboard only…),
- what happened instead.

Accessibility problems are treated as bugs, not feature requests.
