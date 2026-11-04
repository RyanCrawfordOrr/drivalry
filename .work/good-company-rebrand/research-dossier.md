# Research dossier — Good Company rebrand

## Scope and assumptions

Update the existing local Flutter app and its checked-in store artwork to the user-approved Good Company concept. The selected reference is the 1920 × 1920 icon and 2560 × 1440 banner from `outputs/branding-sets-v2/`; do not modify the source references. The reference uses a cream lowercase-d-like mark with a coral dot on an aubergine ground. Representative sampled pixels are approximately aubergine `#392837`, cream `#F9ECDD`, and coral `#F08566`. The work changes presentation only; it must not change driving, scoring, privacy, account, or network behavior. Existing score bands are semantic and should remain meaningful.

The repo has Flutter 3.44.6 / Dart 3.12.2 in its configured SDK cache, existing Material 3 themes, a scalable brand painter, and a `flutter test` art harness with eight seeded real-widget scenes and native launcher output. The Drive map scene uses a painted stand-in for a platform map, so it must not be described as a real device capture. App screenshots and mock data require human review against the actual shipping build. The app currently declares both iPhone and iPad support. No store publishing or code upload is authorized by this request.

## Source coverage and findings

| Source | Type / relevance | Evidence and impact |
| --- | --- | --- |
| [Flutter ColorScheme.fromSeed][1] | Official Flutter API; applies to existing Flutter Material 3 project | A seed creates harmonious light/dark schemes; specific color roles can be overridden, but manual overrides need contrast checks. Use the existing theme rather than adding a dependency. |
| [Flutter themes cookbook][2] | Official implementation guide | ThemeData is inherited by Material widgets and is the appropriate single place for app-wide colors. Existing widgets with explicit colors must be checked separately. |
| [Flutter golden test API][3] | Official Flutter test documentation | Font rendering differs by platform and Flutter version; tests need real font loading. Existing harness explicitly loads Roboto and platform fallback fonts. |
| [Android adaptive icons][4] | Official Android guidance, updated 2026-10-22 | Adaptive foreground, background, and optional monochrome are 108 dp layers; artwork must fit within the central 66 dp safe area for OEM masks. Existing pipeline already has the layers and must preserve that property. |
| [Android splash screens][5] | Official Android guidance, updated 2026-10-29 | Android 12+ uses a system splash and a single opaque background; its icon is masked. The existing v31 resource and legacy splash must share the new brand. |
| [Google Play icon specifications][6] | Official Google Play design guide, updated 2026-10-20 | Listing icon is a full-square 512 × 512 PNG in sRGB, no baked outer mask or shadow; max 1 MB. Google applies the mask. |
| [Apple screenshot specifications][7] | Official App Store Connect reference, accessed 2026-11-03 | One Dynamic Island medium iPhone screenshot is required, and one 13-inch iPad screenshot if iPadOS is supported; screenshots must have no alpha. 1320 × 2868 is an accepted large-iPhone size; 1206 × 2622 is an accepted medium-iPhone size. The existing repo only provides large and older iPhone sets, so add the medium set. |
| [Apple asset best practices][8] | Official marketing and review guidance | Screenshots should show the app in use, have short readable wording, and represent the real experience accurately. |
| [Google Play listing best practices][9] | Official Play guidance | Screenshots should highlight in-app experiences and represent functionality accurately; promotional text should be minimal and not make unverifiable claims. |

## Options and trade-offs

The existing Flutter painter and art tests are the project-maintained source for assets; adapting them preserves regeneration, size variants, and consistency between code and store files. A one-off bitmap replacement alone would drift when the owner regenerates assets. Use the approved design as the visual reference and preserve its distinctive silhouette and palette. Avoid introducing fonts or packages without a practical need and license review; the existing Roboto/material fonts are already part of the installed SDK.

A genuine device capture is preferable for final approval of platform UI, especially the Drive map, but can require a configured phone, simulator, or Android emulator. If unavailable, the seeded widget renderer is a reproducible fallback and must be labeled honestly. An iPad image must depict a real tablet-layout widget, not a stretched or mislabeled phone mockup. Android Auto assets require a Desktop Head Unit capture and are outside the ordinary phone-image renderer.

## Compatibility, security, privacy, and licensing

No new dependencies, permissions, credentials, or services are planned. The existing user-selected local computer and project remain in use; no cloud transfer or publishing. Preserve the repo's current navigation, data models, behavioral logic, and accessibility semantics. Retain semantic score colors unless there is a verified reason to change them. Flutter's startup and the Android SDK need verification in this user's environment; the configured Android SDK location returned access denied to the current execution account, and an independent adb path could not connect to its server. iOS device builds require an Apple toolchain not present on Windows.

## Open risks

The checked-in art renderer was written before Apple's current medium-iPhone requirement. It can skip SQLite-backed scenes when native SQLite is unavailable; output existence and test counts must be checked rather than assuming success. Logo and text legibility should be checked at both full size and small launcher scale. Store submission and trademark clearance are not verified by producing artwork.

## References

[1]: https://api.flutter.dev/flutter/material/ColorScheme/ColorScheme.fromSeed.html "Flutter ColorScheme fromSeed"
[2]: https://docs.flutter.dev/cookbook/design/themes "Flutter themes"
[3]: https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html "Flutter golden image testing"
[4]: https://developer.android.com/develop/ui/compose/system/icon_design_adaptive "Android adaptive icons"
[5]: https://developer.android.com/develop/ui/views/launch/splash-screen "Android splash screens"
[6]: https://developer.android.com/distribute/google-play/resources/icon-design-specifications "Google Play icon design specifications"
[7]: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/ "App Store screenshot specifications"
[8]: https://developer.apple.com/app-store/asset-best-practices/ "App Store asset best practices"
[9]: https://support.google.com/googleplay/android-developer/answer/13393723?hl=en "Google Play listing best practices"
