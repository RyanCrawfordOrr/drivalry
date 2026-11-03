# Drivalry store and brand art

The Good Company identity uses a cream lowercase **d**, a coral dot, and an aubergine background. The shared mark lives in `app/lib/app/brand/drivalry_mark.dart`; app colours live in `app/lib/app/theme.dart`. Store graphics are generated from the same mark and from app widgets with seeded example data.

## Regenerate

From the project’s `app` directory, with the existing Flutter SDK and dependencies installed:

```powershell
$env:DRIVALRY_ART = "1"
flutter test test/art/render_art_test.dart
Remove-Item Env:DRIVALRY_ART
```

To render only specific outputs, set `DRIVALRY_ART_ONLY=icons,brand,01-drive` before the command. Without `DRIVALRY_ART`, the renderer skips rather than changing image files. The test log identifies every generated image and any skipped scenes; SQLite must be available for the seeded screens.

## Store files

| File | Size | Use |
| --- | --- | --- |
| `play/icon-512.png` | 512 × 512 | Google Play listing icon; square, with no baked-in rounding or shadow |
| `play/feature-graphic-1024x500.png` | 1024 × 500 | Google Play feature graphic |
| `play/phone/*.png` | 1080 × 1920 | Eight Google Play phone screenshot drafts, in filename order |
| `appstore/icon-1024.png` | 1024 × 1024, RGB | App Store icon; also embedded in the iOS asset catalog |
| `appstore/iphone-medium/*.png` | 1206 × 2622, RGB | Required Dynamic Island medium-iPhone screenshot class |
| `appstore/iphone-6.9/*.png` | 1320 × 2868, RGB | Optional large-iPhone screenshots |
| `appstore/iphone-6.5/*.png` | 1284 × 2778, RGB | Optional older large-iPhone screenshots |
| `appstore/ipad-13/03-league.png` | 2064 × 2752, RGB | 13-inch iPad screenshot draft, required when the app supports iPad |
| `social-preview-1280x640.png` | 1280 × 640 | Repository social preview |
| `../docs/assets/banner-1600x480.png` | 1600 × 480 | README banner |
| `listing.md` | — | Existing store listing draft; verify every claim before use |

The iPad image is the real league widget rendered at tablet dimensions, not an enlarged phone image. All screenshots are **draft marketing compositions** of real Flutter widgets with example accounts and data, rather than captures from a shipping device. The Drive map uses a painted stand-in because the platform map cannot render in the headless test. Device chrome is drawn, and the iOS mockups use the test renderer’s Roboto font in place of the iOS system font. Before submission, compare each image and its claims with the actual release build; replace the map and any other image as needed with genuine device captures. Store acceptance has not been checked.

## Inside the app

| Path | Contents |
| --- | --- |
| `app/lib/app/brand/drivalry_mark.dart` | Scalable colour and monochrome marks |
| `app/lib/app/theme.dart` | Light and dark Material colour roles |
| `app/lib/features/stats/wrapped_cards.dart` | Tonal season and share cards |
| `app/android/app/src/main/res/mipmap-*/ic_launcher_*.png` | Adaptive foreground, background, monochrome and legacy launcher icons |
| `app/android/app/src/main/res/drawable/ic_stat_tracking.xml` | Monochrome tracking notification mark |
| `app/android/app/src/main/res/values/colors.xml` and launch resources | Aubergine Android splash background |
| `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` | iOS launcher and App Store icon sizes |
| `app/ios/Runner/Assets.xcassets/LaunchImage.imageset/*.png` and `Base.lproj/LaunchScreen.storyboard` | iOS launch mark and aubergine background |

Brand reference colours: aubergine `#392837`, cream `#F9ECDD`, coral `#F08566`. Semantic driving-score and safety colours remain separate from the brand palette. The Android adaptive mark stays within the 66 dp safe area.

## Remaining release checks

- Build and inspect on real Android, iPhone, and iPad devices, including dark/light appearance, launcher masks and splash screens. An iOS build requires Xcode on a Mac.
- Capture Android Auto review screenshots on the Desktop Head Unit if that form factor is declared (`docs/11-owner-setup.md`, Part 7).
- Review listing copy, privacy disclosures, screenshots, supported form factors, and platform policies against the release build before uploading. No assets were published by the renderer.
- Promo video is optional and is not included.

Platform references: [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) and [Google Play icon specifications](https://developer.android.com/distribute/google-play/resources/icon-design-specifications).
