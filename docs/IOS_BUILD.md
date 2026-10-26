# iOS Build

```bash
tools/build_ios.sh export     # Godot -> Xcode project only
tools/build_ios.sh archive    # + unsigned release archive   (default)
tools/build_ios.sh ipa        # + signed .ipa                (needs an Apple ID in Xcode)
tools/build_ios.sh upload     # + upload to App Store Connect
```

Output lands in `../TheDevouring-build/ios/` — deliberately a **sibling** directory, see gotcha 2.

| | |
| :-- | :-- |
| Bundle ID | `com.royz.thedevouring` |
| Team | set `TEAM_ID` env var (empty in repo) |
| Deployment target | iOS 15.0 |
| Devices | iPhone + iPad (universal), **portrait only** |
| Renderer | `gl_compatibility` (OpenGL ES 3) — right choice for a 2D pixel game |
| Architecture | arm64 |
| Encryption | `ITSAppUsesNonExemptEncryption = false` (skips per-build export compliance) |

## Current state

- ✅ Godot iOS export template 4.7.1 installed
- ✅ Export config validates
- ✅ Xcode project generates cleanly
- ✅ `xcodebuild archive` → **ARCHIVE SUCCEEDED**, arm64, passes `-validate-for-store`
- ✅ Icons (48 appiconset entries incl. dark + tinted), launch storyboard, PrivacyInfo.xcprivacy
- ⛔ **Signing blocked**: Xcode has no Apple ID signed in on this machine
- ⛔ **iOS Simulator blocked**: upstream Godot ships an x86_64-only simulator library (gotcha 3)

### The one thing Ian has to do

```
Xcode → Settings → Accounts → + → Apple ID → sign in
```

`defaults read com.apple.dt.Xcode IDEProvisioningTeams` currently reports *no* teams, and both
`archive` with automatic signing and `-exportArchive -allowProvisioningUpdates` fail with
`error: exportArchive No Accounts`. Cloud-managed signing needs a live Xcode account session; there
is no command-line way to create one. After signing in:

```bash
tools/build_ios.sh ipa      # registers the App ID + writes a signed .ipa
# then create the app record at appstoreconnect.apple.com (Apps → + → New App)
tools/build_ios.sh upload   # sends the build to TestFlight
```

That order matters — see the chicken-and-egg note in gotcha 5.

---

## Gotchas paid for in full, so nobody pays again

### 1. iOS export fails with a *blank* error message

The single worst one. `Godot --export-release "iOS"` prints:

```
ERROR: Cannot export project with preset "iOS" due to configuration errors:
```

…and then nothing. The cause is in `editor/export/editor_export_platform_apple_embedded.cpp`:

```cpp
if (!ResourceImporterTextureSettings::should_import_etc2_astc()) {
    valid = false;          // ← no text appended to the error string
}
```

**Fix:** `rendering/textures/vram_compression/import_etc2_astc=true` in `project.godot`. It is set;
do not remove it.

Two things make this hard to diagnose. First, the check appends nothing. Second,
`has_valid_project_configuration()` ends with `r_error = err;` — an **assignment**, not an append —
so it *overwrites* any message `has_valid_export_configuration()` had already produced. A real
error from the first function plus a silent failure in the second yields an empty string.

Diagnostic trick: deliberately break something that *does* report (blank the team ID). If a message
appears, messages work, and the real failure is a silent one.

### 2. Never export into the project directory

Godot resolves an export path under the project as `res://…`, then tries to read its own output back
as game resources:

```
ERROR: Can't open file from path 'res://build/ios/.../Icon-40_dark.png'
```

Harmless but alarming, and it pollutes the import cache with the entire Xcode project. Export to a
sibling directory. The build script does.

### 3. The iOS Simulator does not work on Apple Silicon

Godot 4.7.1's official template contains:

```
libgodot.ios.debug.xcframework/ios-arm64_x86_64-simulator/libgodot.a  →  lipo -archs: x86_64
```

The directory name claims arm64 + x86_64; the library is **x86_64 only**. So on an Apple Silicon Mac:

- an arm64 simulator build fails to link (`ld: symbol(s) not found for architecture arm64`)
- an x86_64 simulator build links fine, but `simctl install` rejects it —
  `Failed to find matching arch for input file`

Options, in order of cost: test on a real device; or compile an arm64-simulator engine library from
Godot source (`scons platform=ios ios_simulator=yes arch=arm64`) and drop it into the template zip.
There is no configuration fix.

### 4. `custom_template/debug` must be present and empty, not absent

```cpp
if (p_preset->get("custom_template/debug") != "") { /* treat as a custom template path */ }
```

A missing key returns a nil `Variant`, and `nil != ""` is **true** in Godot, so an absent key is read
as "a custom template was specified" — pointing at nothing. Result: `Custom debug template not
found.` Keep `custom_template/debug=""` and `custom_template/release=""` in the preset.

### 5. App ID registration is a chicken-and-egg

A brand-new bundle ID's App ID isn't registered with Apple until a provisioning pass runs, so it
won't appear in App Store Connect's "New App" bundle-ID dropdown. But `destination=upload` fails at
`FetchAppRecord` *before* provisioning. Break the loop with `destination=export` first
(`ios/ExportOptionsLocal.plist`), which provisions and registers the App ID without needing an app
record — then create the record, then upload (`ios/ExportOptions.plist`).

### 6. Godot 4.7 changed the iOS icon preset schema

Older 4.x keys like `icons/spotlight_40x40` silently do nothing. 4.7 wants `icons/icon_1024x1024`
(plus `_dark` / `_tinted` appearance variants), `icons/ios_128x128`, `ios_136x136`, `ios_192x192`,
`spotlight_120x120`, `notification_76x76`, `notification_114x114`. Godot derives the per-size
dark/tinted variants from the 1024 ones automatically — 48 appiconset entries from 3 source images.

Ground truth for any future schema change:

```bash
strings ~/Downloads/Godot.app/Contents/MacOS/Godot | grep -E '^icons/'
strings ~/Downloads/Godot.app/Contents/MacOS/Godot | grep -E '^application/'
```

`storyboard/use_launch_screen_storyboard` and `application/generate_simulator_library_if_missing`
no longer exist either.

### 7. Godot writes empty privacy purpose strings

The template emits `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` and
`NSPhotoLibraryUsageDescription` unconditionally, **empty**, for a game that touches none of those
APIs. An empty purpose string is worse than no key — review flags it. `tools/build_ios.sh` deletes
any of the three that came out empty, after export and before archive. `modules/camera=false` is
also set in the preset.

---

## Safe areas

`canvas_items` stretch with `expand` aspect means the 480×960 design viewport becomes ~480×1040 on a
19.5:9 iPhone. The extra height is free screen — but anything bottom-anchored then sits *under the
home indicator*, where a swipe-up dismisses the app instead of picking a dialogue option.

`src/autoload/safe_area.gd` converts `DisplayServer.get_display_safe_area()` from physical pixels
into canvas units and insets each UI root. It clamps any single inset to 20% of the screen and
treats an implausible report as zero, so a bad safe-area value can't shove the UI into the middle of
the screen. Scrims and backdrops stay deliberately full-bleed; only readable content is inset.

**This is the one part of the iOS work that has not been visually verified**, because of gotcha 3.
It is correct by construction and inert on desktop (macOS reports no insets), but it wants a real
device before shipping.

## Screenshots for the App Store

Apple wants 6.9" (1320×2868) and 6.5" portrait. The game renders at a 480-wide design viewport, so
capture at an integer multiple and scale with **nearest-neighbour** — never bilinear, or the pixel
art turns to mush. `src/tools/Capture.tscn` writes frames to `user://captures`; upscale ×3 to
1440×2880 and crop, or re-run the harness with a larger window override.
