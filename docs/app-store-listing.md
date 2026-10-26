# Mac App Store listing

The English text used in App Store Connect, kept here so later versions start from it. The other 13
languages, and the screenshot headlines, are in `app-store-listing/<language>.json`. Screenshots are made
by `scripts/screenshots/make.sh` into `screenshots/<language>/`.

**Name:** Unmuffle

**Subtitle** (30 characters max): Clean up voices in videos

**Category:** Photo & Video (primary), Utilities (secondary)

**Price:** Free

**Copyright:** 2026 Easy Reps Fitness Inc

**Promotional text** (170 characters max):

> Drop in a video, hear the cleaned-up voice right away, and export. Free, open source and private:
> everything happens on your Mac.

**Keywords** (100 characters max):

```
noise,denoise,remove,audio,voice,video,podcast,enhance,clean,background,loudness,mic,speech,sound
```

**Support URL:** https://github.com/iAlborz/Unmuffle/issues

**Marketing URL:** https://github.com/iAlborz/Unmuffle

**Privacy Policy URL:** https://github.com/iAlborz/Unmuffle/blob/main/PRIVACY.md

**App Privacy:** Data Not Collected

**Age rating:** 4+ (no objectionable content)

**Screenshots** (2560 × 1600): `docs/screenshots/simple.png`, `adv.png`, `drop.png`

**Notes for App Review:**

> No account is needed. Open or drop any video that has speech in it. In Simple mode the video plays
> with the cleanup applied; press Export to save a copy. Audio is processed on the Mac by the bundled
> FFmpeg libraries (LGPL), which run as helper tools inside the app's sandbox.

## Description

Unmuffle cleans up the voice in your videos. Drop in a screen recording, a vlog, an interview or a video call, and it removes background noise, evens out the volume and makes speech clearer, without touching the picture.

SIMPLE BY DEFAULT
• Three choices: enhance the audio, boost the voice or give it a podcast tone, and remove background noise.
• The video plays with the cleanup applied as soon as you drop it in, so you hear the result right away.
• Press Export and a copy is saved. The original is never changed.

EVERY CONTROL WHEN YOU WANT IT
• Noise reduction that measures the noise in your recording and sets itself.
• Noise gate, rumble and hiss filters, and an 8-band EQ you can drag.
• Compressor and loudness normalization to the −16 LUFS podcast standard.
• Trim the start and end, and cut out long pauses automatically.
• Switch between Original and Processed while it plays to compare.

THE PICTURE STAYS AS IT WAS
Unless you cut something, the video stream is copied byte for byte. When you do cut, the Mac's hardware encoder re-encodes it at the original bitrate.

PRIVATE AND OPEN SOURCE
Everything happens on your Mac. Unmuffle makes no network connections and collects no data. The source code is on GitHub under the MIT license.
