---
title: Teleprompt
date: 2024-07
status: wip
category: product
tags:
  - ios
  - ipados
  - macos
url: https://teleprompt.fyi
links:
  source: https://github.com/arfct/teleprompt.live
media:
  - src: reading.png
    caption: The reading view on an iPad, where the lines already spoken have dimmed and the unstressed words are set lighter
    alt: A dark iPad screen of Mark Twain's Advice to Youth, the first lines dimmed and later lines in bright white
  - src: library.png
    caption: The script library on an iPhone, a grid of script previews with their dates and word counts
    alt: An iPhone screen titled Scripts with a grid of script cards, among them Podcast Intro and Conference Talk
  - src: landscape.png
    caption: The same script on an iPhone turned to landscape
    alt: A wide iPhone screen of large white text on black, the top lines dimmed
credits: [dps]
unconfirmed: [status]
---

A script in Teleprompt scrolls as it is read aloud, at the pace of the person reading it. Speech recognition on the iPhone or iPad matches the spoken words against the text, and the scroll is modelled on a flywheel. Speaking spins it up toward the speaker's average pace, a pause lets it coast to a stop under friction, and a weak spring draws the current line toward the middle of the screen. Only the acceleration is ever adjusted, so a change of pace or of line does not show as a jolt, and the text never runs backward.

When a speaker skips a sentence, the tracker moves ahead once enough of the later words match. Words already spoken fade. Those that go unstressed in speech, such as "the", "of" and "would", are set in a lighter weight so that the others stand out, while "not" and "never" keep their full weight.

Scripts are typed, pasted or opened from Google Docs, and they stay on the device. The same code builds for the Mac with Mac Catalyst. The app is built from the repository and is not on the App Store.

Swift, SwiftUI, Speech framework. 2024.
