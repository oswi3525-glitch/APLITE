# APLite audio: root cause, repair and verification

This document records the audio investigation for the 1.1.x maintenance line. It is written from
the source in this repository. **No device test is claimed here** — the Linux development container
has no Xcode, simulator or iPhone. The on-device checklist at the end is the verification that must
be run before calling the audio fix complete.

## Architecture: one session for the whole process

Guest apps are `dlopen`-ed into APLite's process. That means every sound source shares the single
process-wide `AVAudioSession`:

| Source | File | What it used to do |
| --- | --- | --- |
| Launch | `App/AppDelegate.swift` → `Desktop/ScreenRecorder.swift` (`MediaControl.start`) | `setActive(true)` with the **default** category (silent-switch sensitive, stops other audio). |
| Read aloud | `Desktop/WebFeatures.swift` | `setCategory(.playback, .spokenAudio)` but **never activated** the session. |
| Voice typing | `Input/InputExtras.swift` | `setCategory(.playAndRecord, …)`, then `setActive(false)` on stop — **deactivating the whole desktop's audio**. |
| Quick Look media | `Desktop/QuickLook.swift` | Created an `AVPlayer` without touching the session. |
| Web pages / guest apps | `Desktop/DeskWindow.swift`, `Guest/` | Rely on whatever category was left behind. |
| Interruptions / routes | — | **Nobody listened.** A phone call, Siri, AirPods or an HDMI change could leave the session inactive forever. |

## Root causes of "no sound"

1. **Wrong baseline category.** The default category is silenced by the iPhone's ring/silent switch
   and is not appropriate for HDMI / AirPlay media. It was never set to `.playback` at launch.
2. **Voice typing deactivated the session.** `setActive(false)` on stop is process-wide. Web videos,
   guest apps and Quick Look lost their audio until the app was restarted.
3. **Category without activation.** Read Aloud changed the category but left an inactive session.
4. **No interruption recovery.** When another app's audio or a call interrupted APLite, nothing
   called `setActive(true)` again after the interruption ended.
5. **No route recovery.** Unplugging headphones / a display could leave the session inactive.
6. **Guest-app category leaks.** A guest app that changes the category and closes left the new
   category in place for the desktop.

## Repair

- `App/AudioSessionManager.swift` is now the **only** owner of `AVAudioSession`. It keeps an active
  `.playback` + `.default` session with `.mixWithOthers` for the whole app lifetime, switches to
  `.playAndRecord` only while voice typing listens, and **restores playback** afterwards.
- It observes `AVAudioSession.interruptionNotification`, `routeChangeNotification`, app
  foreground/background and the guest-window notification, reactivating the correct mode when safe.
- Guest apps that deliberately changed the category are not overridden while they are open; the
  playback baseline is restored when the last guest window closes.
- `MediaControl`, `ReadAloud`, `VoiceTyping` and `QuickLook` no longer write to the session directly.
- `AVRoutePickerView` on the iPhone remains the system route picker (AirPods / speaker / HDMI / AirPlay).
- A mute tile was added to Control Center (quick panel tile 5) using the existing `MediaControl`
  volume HUD — no fake player was introduced to mask any of the above.
- **No Guest Engine file was changed.**

## Diagnostics

`App/AudioDiagnostics.swift` holds the report model. Audio events are kept in a bounded ring buffer
(80 entries) so diagnostics cannot leak memory. Get a report in three ways:

1. Desktop Settings → Sound → **Copy audio diagnostics** (copies to the iPhone clipboard).
2. Debug build launch argument `-iDeskScript "audio"` logs the full report with `[APLite-audio]`
   to the Xcode console; `audio:copy` also copies it.
3. `OSLog` subsystem `com.hieuk.aplite`, category `Audio`, tag `[APLiteAudio]` for every event.

The report contains: category, mode, options, active state, volume, sample rate, I/O buffer, output
and input ports, built-in-speaker / headphones / Bluetooth / HDMI / AirPlay flags, interruption state
and the most recent events.

`APLiteTests` unit-tests the ring buffer, port classification, route flags and report format. CI runs
these on an iOS Simulator and uploads the test log on failure.

## On-device verification checklist (NOT yet performed in this repository)

- [ ] Launch with HDMI/USB-C display: video on a web page produces sound through the display.
- [ ] AirPlay to Apple TV: sound follows the route selected with the iPhone's Sound button.
- [ ] Bluetooth headphones connect/disconnect mid-playback: sound resumes, no permanent silence.
- [ ] Voice typing start → stop: desktop audio keeps playing (this was the main regression).
- [ ] Incoming call / Siri during playback: sound resumes after the interruption ends.
- [ ] Open a guest app that plays audio, close it, then play a web video: sound returns.
- [ ] Silent switch on/off: media keeps playing (`.playback` category).
- [ ] Quick Look on an `.m4a`/`.mp3` file, then close: sound stops and other audio is unaffected.
- [ ] Copy diagnostics from Settings and confirm the report shows the active route.

## Limits (by iOS design, not defects we can fix in this sandbox)

- APLite does **not** declare the `audio` UIBackgroundMode. Switching to another *system* app
  therefore suspends audio by iOS design; returning to APLite reactivates the session. We
  deliberately did not add a background mode: it would keep the device awake and is not needed for
  switching between guest apps **inside** APLite, which the guest-window hook handles.
- `AVRoutePickerView` is the only way for an app to change the output route. It must be tapped on
  the iPhone screen (it is in the controller UI under "Sound"); it cannot be driven from the desktop.
- Guest apps are loaded in-process and may set their own category. APLite does not override a
  category while a guest app is open; it restores the playback baseline when the last one closes.

Unresolved issues found during these tests must be listed in `CHANGELOG.md` under "Known issues"
and must not be marked as verified.
