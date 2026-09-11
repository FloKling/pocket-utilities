# Pocket Utilities

A native, offline macOS menu-bar utility suite written entirely in Swift. Independently implemented window-management behavior inspired by SizeUp, plus Keep Awake, Mouse Jiggler and local clipboard history. One menu-bar icon, no Dock icon during normal use, no third-party packages.

**Requires macOS 14 or later, an Apple Silicon Mac and Swift 6.0 or later.** Uses Swift 5 language mode with modern SwiftUI/AppKit APIs; does not require Rosetta. The Java/Spring repository baseline does not apply to this explicitly Swift-native application.

## Build and launch

From Terminal:

```sh
cd ~/pocket-utilities
./scripts/test.sh
./scripts/build-app.sh
open "dist/Pocket Utilities.app"
```

Output: `dist/Pocket Utilities.app`. The script builds release/arm64, assembles the agent app bundle, ad-hoc signs it, verifies the signature and prints its architecture. Do not run a bare `swift run` binary for regular use: macOS privacy permissions should be associated with the stable app bundle.

Xcode is optional for building. Current Command Line Tools contain Swift, AppKit, CryptoKit and the SDK. The test script also locates Swift Testing when using Command Line Tools. With full Xcode, open `Package.swift` for editing and debugging; the packaging script produces the normal menu-bar `.app`. Xcode must have its license accepted and first-launch setup completed if selected as the developer toolchain. The scripts do not accept licenses or change the globally selected toolchain.

For this restricted agent environment, prepend `POCKET_DISABLE_SWIFTPM_SANDBOX=1` to the build/test commands to avoid nesting SwiftPM's subprocess sandbox. This is a build-tool option only; it is not an app entitlement. Caches live under `.build/`.

Keep the built app in a stable location. You can copy it to `~/Applications` before granting permissions. A paid Developer account is not required. Ad-hoc signing works for personal local builds; it does not provide Developer ID distribution or notarization. If a downloaded copy is quarantined, macOS may require an explicit Open/Open Anyway action under Privacy & Security. Do not disable Gatekeeper globally. Rebuilding an ad-hoc signed binary can invalidate Accessibility or Keychain trust; remove/re-add the app in Accessibility if needed. A stable development signing identity can reduce repeated prompts, but is optional.

## Local signing without an Apple account

A persistent self-signed **Code Signing** certificate can provide a stable identity for local updates. In Keychain Access, use Certificate Assistant → Create a Certificate, choose Self Signed Root and Code Signing, and keep the same certificate/private key for subsequent builds. No Apple account is required. This does not provide Developer ID distribution or notarization.

List available identities with `security find-identity -v -p codesigning`, then pass the certificate's SHA-1 fingerprint:

```sh
POCKET_SIGNING_IDENTITY="YOUR_CERTIFICATE_SHA1" ./scripts/build-app.sh
```

If an explicitly selected identity is unavailable, the build fails instead of silently using ad-hoc signing. Without this variable, local builds remain ad-hoc and print a warning. After switching identity, add the current app to Accessibility again once; permission persistence across subsequent updates must be verified on your Mac. Keep the app at a stable path. Do not commit or share the signing private key.

The bundled `Resources/AppIcon.icns` uses the menu bar's four-square motif. Regenerate it after editing the drawing:

```sh
mkdir -p .build
swift -module-cache-path .build/module-cache scripts/generate-icon.swift .build/AppIcon.iconset
python3 scripts/pack-icon.py .build/AppIcon.iconset Resources/AppIcon.icns
```

## First use and permissions

Click the four-square menu-bar icon → Settings → Permissions. Accessibility is required to control other apps' windows, run the global event tap, jiggle the pointer and optionally synthesize paste. Click **Open Accessibility Settings…**, enable **Pocket Utilities**, then **Recheck Permission & Start Shortcuts** or restart. The menu also retries shortcut setup when opened. macOS may request Input Monitoring for the event tap; grant it if requested and restart. There is no repeating permission prompt.

Keep Awake and copying entries back to the clipboard work without Accessibility. For clipboard history without its global shortcut, use **Clipboard → Show History…**. Newer macOS releases may additionally show system clipboard privacy prompts. Denial or empty pasteboard access is handled as no new capture.

Keep Awake and Jiggler always launch OFF. Clipboard recording starts enabled, but **memory-only**, with password-manager exclusions and a two-second stabilization period. Switch recording off in Settings or temporarily pause it in the menu. Persistence is explicitly opt-in.

## Window management

- Halves, quarters, thirds, two-thirds, maximize, center and SnapBack.
- Next/previous display, plus next display and maximize.
- Configurable outer margin, horizontal and vertical gaps in logical points.
- Uses `NSScreen.visibleFrame` to account for menu bars and Dock placement. Converts AppKit coordinates into Quartz/Accessibility coordinates against the primary display; negative origins, portrait displays and different point resolutions are supported.
- Display transfers preserve proportions within usable screen frames and clamp the result to the destination. SnapBack stores up to 100 window references in memory, restoring the frame immediately before the last successful/partially applied operation. Repeated SnapBack toggles the two frames. Failed or no-op actions do not overwrite useful history.
- Window lookup prefers the focused window, then the focused control’s containing window, then the main window, and finally a single entry in the app’s window list. Multiple unidentified windows are rejected rather than guessed. Accessibility response errors are reported separately from missing focus attributes.
- Dialogs, sheets, minimized and native full-screen windows are skipped. Applications can refuse resizing, impose minimum sizes or expose incomplete Accessibility trees. Rejected Accessibility writes are surfaced without crashing; partial moves retain SnapBack. Accepted writes do not require an immediate exact geometry match: apps may enforce minimum sizes or update their geometry asynchronously. Such windows may be wider than the requested half without showing an error dialog.

### Default global shortcuts

Every default uses **Control + Option + Command** plus the key below. All window actions, Clipboard History, Toggle Keep Awake and Toggle Mouse Jiggler can be changed or cleared in Settings → Shortcuts. Key positions are physical macOS key codes; labels reflect the recorded keyboard input. Defaults use US key labels, so record your own bindings if your keyboard layout differs.

| Action | Key |
| --- | --- |
| Left / Right / Top / Bottom half | Corresponding arrow |
| Top left / Top right / Bottom left / Bottom right | U / I / J / K |
| Left / Center / Right third | 1 / 2 / 3 |
| Left / Right two-thirds | 4 / 5 |
| Maximize | Return |
| Center | C |
| SnapBack | Delete (Backspace) |
| Next / Previous display | Period / Comma |
| Next display and maximize | M |
| Clipboard history | V |

Use Configure Shortcuts… in the menu to open the editor directly. Click a recorder, press the new combination, Escape to cancel or unmodified Delete to clear. Modified Delete can be assigned. Restore Default Shortcuts restores window/clipboard defaults and clears the optional utility bindings. Changes are saved immediately. Internal duplicate bindings are rejected. An event tap handles and consumes matching key-down events, ignores repeats and is suspended during shortcut recording. Nonmatching keys are neither stored nor logged. There is no reliable public registry of all third-party shortcuts; conflicts with other apps and system-reserved shortcuts require choosing a different binding. Secure Input can prevent global shortcuts from working, especially in password fields. Menu actions remain available.

### Spaces limitation

No reliable documented public API was found for assigning arbitrary third-party windows to a particular Mission Control Space. This implementation deliberately omits that feature. It uses no private CGS/SkyLight APIs, simulated Mission Control dragging or other Spaces hacks. Native full-screen Spaces are left untouched.

## Keep Awake and Mouse Jiggler

Keep Awake uses `kIOPMAssertionTypePreventUserIdleDisplaySleep` with an `IOPMAssertion`. Choose 15/30 minutes, 1/2 hours or indefinitely. One one-shot timer expires a timed session; the deadline is also checked after wake and when the menu opens. Off and normal termination release the assertion immediately; macOS also releases process assertions on process exit. The assertion prevents automatic display dimming/sleep and, while the display stays awake, idle system sleep. This also avoids locking triggered by display sleep. It does not guarantee suppression of separate screen-saver timers or managed security policies, and does not override manual locking, explicit sleep or lid closure. It never unlocks a locked session or changes macOS security settings. No simulated input is used by this module.

Jiggler is a separate service with a 60-second default interval (configurable from 10–3600 seconds). Subtle mode posts a one-point pointer movement and return; regular mode uses two points. The pair is queued without a delayed restore, avoiding accumulated drift. It skips held mouse buttons/modifiers, keyboard/mouse/scroll activity within five seconds, unavailable sessions, special presentation modes, full-screen-sized windows and configured app exclusions. No Accessibility window tree is read for Jiggler; it uses public on-screen window bounds. If ordinary window metadata is unavailable it skips the jiggle.

Public APIs cannot reliably identify every game, relative-pointer mode or race with input that begins after a safety check. For such apps, turn Jiggler off or exclude their bundle identifiers. This is a best-effort convenience feature, not an absolute guarantee against interference or a replacement for Keep Awake.

## Clipboard history and privacy

**Clipboard history stays on this Mac.** The app contains no network client, HTTP/WebSocket APIs, telemetry, analytics, cloud synchronization, crash-upload service, external SDK or clipboard payload logging. There are no networking or iCloud entitlements. The only URL opened by the app is the local macOS Accessibility settings pane; URL clipboard entries are restored as data, never fetched or opened. File entries preserve references; the app does not read referenced files or resolve remote URLs. Rich HTML is never rendered as a web page.

Supported representations: plain text, RTF/RTFD, HTML, URL, file URL, PNG and TIFF. Multi-item pasteboard contents and their supported representations are preserved together. Image thumbnails are generated locally with ImageIO at a small pixel size; persistent image payloads are loaded on demand. Unsupported custom representations/file promises are not captured. Oversized items are discarded as a whole, not partially recorded.

The compact floating history panel supports search-as-you-type, arrows, Return, Escape, Command+Delete, pin/unpin, double-click selection and context menus. Pins sort first; new entries follow. By default, selecting an item only restores the system clipboard. Enable **Direct Paste** in the menu bar’s Clipboard section or Settings → Clipboard to restore focus and send Command+V when Accessibility is granted and the original application is still frontmost after reactivation. The switch is saved across launches and applies immediately to double-click and Return selection; the history window closes on selection. Direct Paste is off by default. Without permission, clipboard restore remains functional. Some applications ignore synthetic paste or require manual Command+V.

### Monitoring and sensitive data

macOS general pasteboard has no suitable public cross-process change notification. A one-second tolerant timer checks `NSPasteboard.changeCount`; contents are read only after a change, and, by default, only if that clipboard version survives two seconds. Idle checks do not deserialize content. Recording is suspended while the session or displays are unavailable. Startup, resume, pause and settings changes reset the baseline rather than ingesting old clipboard contents.

Concealed, transient and autogenerated pasteboard markers are always rejected, including common password-manager markers. Built-in bundle-ID exclusions cover 1Password, Bitwarden, KeePassXC, Apple Passwords, Dashlane and LastPass. User exclusions are never silently removed or overridden. The frontmost application observed when a change is detected is used as a source heuristic; macOS does **not** reliably identify the true producer, particularly for background apps or rapid focus changes. Exclusions and short-lived-copy filtering cannot guarantee detection of every password/token/OTP. Pause or disable recording for sensitive work; this app does not claim content-based secret detection.

Restored history items carry an autogenerated marker and are skipped by this recorder. Canonical payload hashes deduplicate identical data even when representation order differs; repeated entries update their timestamp while keeping pin state.

### Storage

- Default: memory-only. No history files or Keychain key are created until persistence is enabled.
- Optional persistence: independent AES-256-GCM encrypted binary property-list payloads plus an encrypted index under `~/Library/Application Support/PocketUtilities/Clipboard`. No database dependency is needed for this bounded store.
- A 256-bit CryptoKit key is stored in the local Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, never next to the files and never marked synchronizable. Directory permissions are 0700 and files 0600. Index and payload writes are atomic. Authentication rejects modified ciphertext.
- If encryption/Keychain/storage fails, recording pauses; it never silently falls back to plaintext. The history panel displays the error. Unlock Keychain and retry the persistence setting, or clear history to recover. Losing the key makes existing history unrecoverable.
- Default limits: 100 items, seven days, 5 MB per item. Configurable within 10–500 items, 1–90 days, 1–20 MB per item. Additional aggregate payload limits: 32 MB memory-only, 256 MB persistent. Encoding, framework caches and thumbnails add overhead beyond these payload budgets.
- Limits also apply to pins. Pruning occurs on capture, startup, settings changes and approximately every minute while the session is available. Expired entries after sleep are pruned on resume or opening history. Orphaned encrypted payloads from interrupted writes are removed.
- Turning persistence OFF intentionally clears both in-memory and stored history. Clear History includes pins; individual deletion removes its payload. Neither action clears the system clipboard. A separate option clears history on **normal** quit; it cannot run after a crash or forced termination.
- Deletion is logical filesystem deletion, not forensic secure erasure on APFS/SSDs. The app does not synchronize data, but user-configured backups can include encrypted files. FileVault and trusted local account access remain useful. Encryption protects stored files; it cannot protect plaintext from a compromised logged-in process while the history is open.

## Architecture

`UtilityCore` contains the pure fractional `LayoutEngine`, window actions, shortcut values, `ClipboardPrivacyFilter` and `HistoryPolicy`. It has no Accessibility dependencies.

`PocketUtilities` contains `AccessibilityService`, `DisplayService`, `WindowManager` and per-window history; `HotkeyManager`; independent `KeepAwakeService` and `MouseJigglerService`; `ClipboardMonitor`, `ClipboardStore`, `ClipboardHistoryController` and `ClipboardHistoryView`; `SettingsStore` and SwiftUI preferences; `MenuBarController` and AppKit lifecycle. Application and UI work is confined to the main run loop. Clipboard work is bounded by item/aggregate limits; unusually large lazy pasteboard producers can still cause a brief main-thread stall when macOS supplies data.

## Verification

`./scripts/test.sh` runs Swift Testing unit tests for halves, quarters, thirds, two-thirds, seams/margins, extreme aspect ratios, display transforms/transfers and centering; per-window SnapBack, no-ops, rejected/partial moves; assertion replacement, expiration and release; exclusion/marker handling, pruning/pins and aggregate budgets, shortcut conflicts; memory-only storage, canonical deduplication, encrypted round trips, ciphertext tampering, key failure, disk deletion and quit policy. Storage tests use temporary directories and injected ephemeral keys; they do not read the system clipboard or modify the user's Keychain. Window and power tests inject collaborators rather than moving real windows or changing sleep behavior.

A noninteractive lifecycle check is available:

```sh
"dist/Pocket Utilities.app/Contents/MacOS/PocketUtilities" --smoke-test
```

It constructs the application and menu, then exits normally. It does not start recording or request permissions. For visual inspection with isolated, unsaved defaults and recording paused:

```sh
open "dist/Pocket Utilities.app" --args --preview
```

Before relying on it daily, manually check on your Mac: grant Accessibility; exercise window shortcuts in Finder/TextEdit; minimum-size windows, dialogs and native full screen; display transfer with different scaling/Dock positions; actual timed sleep assertion expiration; Jiggler safety during dragging/games; clipboard capture/search/selection with harmless text/images/files; exclusions with your password manager; persistence with your Keychain and app-signing identity. Unit tests cannot prove app-specific Accessibility or TCC behavior.

## Public API references

- [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement)
- [CGEvent event taps](https://developer.apple.com/documentation/coregraphics/cgevent)
- [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)
- [IOPM assertion types](https://developer.apple.com/documentation/iokit/iopmlib_h/iopmassertiontypes)
- [NSPasteboard.changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount)
- [CryptoKit AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [Device-local unlocked Keychain accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)
