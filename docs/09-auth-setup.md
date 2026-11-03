# Drivalry: Sign-in setup (owner checklist)

> Everything the app needs for Sign in with Apple and Google through Supabase Auth. All of it is free. Do it once before the friends-and-leagues build goes on phones. Values that are not secret (client ids, team id, bundle id) go in `.env` so the app can read them at build time; the only secret involved (the Apple `.p8` key) is pasted into the Supabase dashboard and never into the repo.

## 0. What the app does

| Platform | Apple | Google |
| --- | --- | --- |
| iOS | Native sheet (`sign_in_with_apple`), id token → `supabase.auth.signInWithIdToken(provider: apple)` | Native (`google_sign_in`), id token → `signInWithIdToken(provider: google)` |
| Android | Not offered at first (would need the Apple web flow and a client secret that expires every six months) | Native (`google_sign_in`) |

Apple's rule: an iOS app that offers Google sign-in must also offer Sign in with Apple. Android has no such rule, so Android ships Google-only and nobody has to rotate an Apple secret.

Supabase settings live at https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/auth/providers.

## 1. Google (both platforms)

Google Cloud project `drivalry`, https://console.cloud.google.com/apis/credentials?project=drivalry.

1. **OAuth consent screen** (left menu → OAuth consent screen, or "Google Auth Platform → Branding"). User type **External**. App name `Drivalry`, support email your Gmail, developer contact your Gmail. Scopes: leave defaults (email, profile, openid). Save. Under **Audience** keep it in *Testing* and add the Gmail addresses of your testers (up to 100), or click **Publish app** once you want anyone to sign in; publishing with only basic scopes needs no verification.
2. **Android client**: Credentials → Create credentials → OAuth client ID → Application type **Android**. Name `Drivalry Android debug`. Package name `app.drivalry`. SHA-1: run on Windows
   ```powershell
   keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | Select-String SHA1
   ```
   (`keytool` is in Android Studio's JBR: `C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`.) Create. Repeat later with the release keystore's SHA-1 as `Drivalry Android release`. Nothing from these clients goes in `.env`.
3. **iOS client**: Create credentials → OAuth client ID → **iOS**. Name `Drivalry iOS`. Bundle ID `app.drivalry`. Create. Copy the **Client ID** (ends in `.apps.googleusercontent.com`) into `.env` as `GOOGLE_IOS_CLIENT_ID`. Also note its reversed form shown on the page (`com.googleusercontent.apps.…`); the app needs it as a URL scheme and derives it from the client id.
4. **Web client** (used as the "server client id" so the id token is issued to one audience on every platform): Create credentials → OAuth client ID → **Web application**. Name `Drivalry Supabase`. Authorised redirect URIs: `https://htqyutdwnnguqatakofx.supabase.co/auth/v1/callback`. Create. Copy **Client ID** into `.env` as `GOOGLE_WEB_CLIENT_ID`. Copy the **Client secret** for step 5 only.
5. **Supabase**: Authentication → Providers → Google → enable. Client ID = the web client id. Client Secret = the web client secret. **Authorized Client IDs** = the web client id, the iOS client id, and (comma-separated) nothing else; the Android client id is not needed because Android tokens are issued to the web client id. Toggle **Skip nonce check** on (Google's native iOS SDK does not return the nonce). Save.

## 2. Apple (iOS)

https://developer.apple.com/account/resources

1. **App ID**: Identifiers → `app.drivalry` (created when you requested CarPlay). Edit → tick **Sign in with Apple** → Save. If it was not created yet: `+` → App IDs → App → explicit bundle id `app.drivalry`, tick Sign in with Apple and Push Notifications.
2. **Supabase**: Authentication → Providers → Apple → enable. In **Client IDs** enter `app.drivalry`. Leave **Secret Key** empty: it is only used for the web flow, which we do not use. Save.
3. Xcode on the Mac (first iOS build): Runner target → Signing & Capabilities → `+ Capability` → Sign in with Apple. This adds the entitlement to `Runner.entitlements`; commit that file.

Nothing goes in `.env` for Apple.

## 3. Turn email sign-in off

Authentication → Providers → Email → disable **Enable Email provider**. Save. The app never shows an email form, and this keeps the project from accepting password sign-ups through the public API.

## 4. Auth settings worth changing

Authentication → URL Configuration: Site URL `https://github.com/RyanCrawfordOrr/drivalry`, Redirect URLs add `app.drivalry://login-callback` (used if a web flow ever appears). Authentication → Settings: leave "Allow new users to sign up" on; the free tier's 50k monthly active users is not a concern.

## 5. `.env` additions

```
GOOGLE_WEB_CLIENT_ID=
GOOGLE_IOS_CLIENT_ID=
```

`.env.example` lists the same two keys blank. The Android client has no id to configure: the SHA-1 registration in step 1.2 is the whole thing, and if it is missing Google returns `DEVELOPER_ERROR` (code 10), which the app shows as "Google sign-in is not configured for this build".

## 6. Check it worked

- Google on Android: install a debug build, tap Continue with Google, pick an account that is a tester (or the app is published). You land on your profile with a generated handle.
- Apple on iOS: tap Continue with Apple, use Face ID. The handle is derived from the name Apple shares the first time; if you "Hide my email", the profile still works because the handle is what matters.
- Supabase → Authentication → Users shows the row; `profiles` has a matching row created by the `on_auth_user_created` trigger from `0001_init.sql`.
