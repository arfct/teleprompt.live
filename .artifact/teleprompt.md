---
title: Teleprompt Live
date: 2024-07
category: product
tags:
  - ios
url: https://teleprompt.fyi
links:
  source: https://github.com/arfct/teleprompt.live
media:
  - src: reading.png
    caption: The reading view on an iPad, with the lines already spoken dimmed and the small words set lighter
    alt: A dark iPad screen of Mark Twain's Advice to Youth, the first lines dimmed and later lines in bright white
  - src: library.png
    caption: The script library on an iPhone, a grid of script previews with dates and word counts
    alt: An iPhone screen titled Scripts with a grid of script cards, among them Podcast Intro and Conference Talk
  - src: landscape.png
    caption: The same script on an iPhone in landscape
    alt: A wide iPhone screen of large white text on black, the top lines dimmed
credits: [dps]
---

Teleprompt Live is a teleprompter for iPhone and iPad that scrolls a script as it is read aloud. Speech recognition on the device matches the spoken words against the script, and the text scrolls to keep the current line in the middle of the screen.

The scroll follows the speaker's average pace and coasts to a stop during a pause. When the speaker skips a sentence, the tracker moves ahead once enough of the later words match. Words already spoken fade, and small words such as "the" and "of" are set in a lighter weight. Scripts are typed, pasted or opened from Google Docs, and are stored on the device.

Version 1.0 is entered in App Store Connect and has not been submitted. It is held until Google's review of the Google Docs sign-in is finished. The same code builds for the Mac with Mac Catalyst.

Swift, SwiftUI, Speech framework. 2024.
