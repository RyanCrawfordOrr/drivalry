# Store and brand art

Everything in this folder, plus the launcher icons inside `app/`, is rendered from one source: the painter in `app/lib/app/brand/drivalry_mark.dart` and the real app screens with seeded data. Nothing is hand-drawn, so a brand change is one edit and one command.

## Regenerate

```powershell
cd C:\Drivalry\app
$env:DRIVALRY_ART = "1"
flutter test test/art
Remove-Item Env:DRIVALRY_ART
```

Takes a few minutes. `DRIVALRY_ART_ONLY=icons,brand,01-drive` limits the run to some outputs. Without `DRIVALRY_ART` the suite skips, so CI never rewrites these files.

## What is where

| File | Size | Used for |
| --- | --- | --- |
| `play/icon-512.png` | 512×512, no alpha | Play Console → Store listing → App icon |
| `play/feature-graphic-1024x500.png` | 1024×500 | Play Console → Store listing → Feature graphic (required) |
| `play/phone/*.png` | 1080×1920 | Play Console → Phone screenshots (upload all, in filename order) |
| `appstore/icon-1024.png` | 1024×1024, no alpha | Also embedded in the Xcode asset catalog; App Store Connect reads it from the build |
| `appstore/iphone-6.9/*.png` | 1320×2868 | App Store Connect → iPhone 6.9" display (required set) |
| `appstore/iphone-6.5/*.png` | 1284×2778 | App Store Connect → iPhone 6.5" display (optional; otherwise the 6.9" set is scaled) |
| `social-preview-1280x640.png` | 1280×640 | GitHub → repo Settings → Social preview |
| `../docs/assets/banner-1600x480.png` | 1600×480 | README header |
| `listing.md` | | The text for both stores |

Inside the app:

| Path | What |
| --- | --- |
| `app/android/app/src/main/res/mipmap-*/ic_launcher_foreground.png`, `_background.png`, `_monochrome.png` | Adaptive icon layers (108 dp), wired by `mipmap-anydpi-v26/ic_launcher.xml` |
| `app/android/app/src/main/res/mipmap-*/ic_launcher.png`, `ic_launcher_round.png` | Legacy icons for Android 7 and older |
| `app/android/app/src/main/res/drawable/ic_stat_tracking.xml` | Status-bar icon (vector, same ribbon) |
| `app/android/app/src/main/res/drawable/launch_background.xml`, `values-v31/styles.xml` | Splash: brand ink behind the mark |
| `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` | All iOS icon sizes, no alpha |
| `app/ios/Runner/Assets.xcassets/LaunchImage.imageset/*.png` | Launch screen mark on the system background colour |

## Still needed from the owner

- **Android Auto screenshots** for the Play form-factor declaration must be captured on the Desktop Head Unit (`docs/11-owner-setup.md` Part 7); Google wants real head-unit captures.
- **iPad.** The Xcode project targets iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`). App Store Connect then demands 13" iPad screenshots. Either set the family to `1` (iPhone only, the sensible choice for a driving app) in Xcode → Runner → General → Supported Destinations, or ask for an iPad set to be rendered.
- **Promo video** (optional on both stores): not made.

## Design notes

- Mark: a road ribbon climbing left to right, dashed centre line cut through, teal destination dot inside the top end. Orange is `DrivalryTheme.seed`, teal `DrivalryTheme.teal`, ink `#111726`.
- The adaptive foreground keeps the artwork inside the 66 dp safe circle; the monochrome layer is the same ribbon in white for Android 13 themed icons.
- Screenshots are real screens on the dark theme inside a drawn phone body, with a headline above. The friends map in the Drive tab is a painted stand-in because Google Maps cannot render off-device; replace that one shot with a device capture before release if you prefer.
