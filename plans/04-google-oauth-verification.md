# Google OAuth verification

What Teleprompt asks Google for, why, and how to get it verified. Status lives in issue #2; this file is the material for the form.

## Project

- GCP project `artifact-teleprompt` (artifact.com organization), owner nicholas@artifact.com.
- App name **Teleprompt**, support email support@artifact.com, logo from `AppIcon.icon`.
- Homepage `https://teleprompt.fyi/`, privacy policy `https://teleprompt.fyi/privacy/`. `teleprompt.fyi` is verified in Search Console (Domain property, DNS TXT in Cloudflare) under the project owner.
- One OAuth client: iOS, bundle `com.artifact.teleprompt-live`, App Store ID 6825103706, team TVA9Z8LD95. The Mac Catalyst build uses the same bundle ID and client.

## Scopes

| Scope | Class | Used by | Justification (for the form) |
| --- | --- | --- | --- |
| `openid`, `userinfo.email`, `userinfo.profile` | Non-sensitive | `GoogleAccount.fetchEmail` | Shows which Google account is connected, so the user can tell which Docs they're seeing and sign out of the right one. |
| `documents.readonly` | Sensitive | `TelepromptView` loads the chosen Doc via `documents.get` | Teleprompt is a teleprompter. When the user picks one of their Google Docs, the app reads that document's text and displays it as a scrolling script. It never edits documents. |
| `drive.metadata.readonly` | Restricted | `GoogleAccount.searchDocs` (`files.list`, Docs only, fields `id,name,modifiedTime`) | To let the user pick which Doc to read, the app lists their Google Docs by name and date and searches them by name. It only reads file names and dates; document text comes from the Docs API, and this scope can't download files. |

**Why not a narrower scope.** `drive.file` only covers files the app created or the user opened through the Google Picker. The Picker is a JavaScript web component with no native iOS or macOS version, so a native app can't use it to let people choose an existing Doc. Listing a user's existing Docs needs Drive metadata access, and `drive.metadata.readonly` is the narrowest scope that provides it. (The app first used `drive.readonly`; it was narrowed before submission.)

**Data handling.** All requests go from the device straight to Google. Teleprompt has no servers. Tokens and the text of opened Docs are stored only on the device (the Docs are cached so they open offline). Nothing is sent to Artifact or any third party. The privacy policy states this and includes the Limited Use disclosure.

## Demo video

**Uploaded:** https://www.youtube.com/watch?v=aSu4vZJ1lug (unlisted, 1:13, recorded in the iPhone 17 simulator with the test account).

Unlisted YouTube video, about 2 minutes, recorded on an iPhone or the simulator with the test Google account. Google wants to see the consent screen with the app's name and the OAuth client ID, and each scope being used.

1. Show the app's name and version (App Store/TestFlight page or Settings → Teleprompt).
2. Open Teleprompt. Library → ⋯ → **Sign In to Google**.
3. Google's sign-in sheet: zoom on the address bar or tap the app name to show the client ID (`656329432531-…`) in the URL. Sign in.
4. Consent screen: pause on "Teleprompt wants access", the Drive (file information) and Docs checkboxes. Select all, Continue.
5. ⋯ menu now shows the account email (userinfo scopes).
6. **+ → Add Google Doc**: the recent Docs list appears (drive.metadata.readonly). Type "sample" to search.
7. Pick "Teleprompt sample script": it opens as a script (documents.readonly). Read a line aloud so it scrolls.
8. ⋯ → **Sign Out of Google**.

## Steps

1. **Publish the app** (Audience → Publish app). Lifts the test-user list and the 7-day token expiry. Users see "unverified app" and the 100-user lifetime cap applies until verification finishes.
2. **Record and upload the demo video** (above).
3. **Submit for verification** (Verification Center → Prepare for verification): scope justifications, video link, confirm the branding.
4. **Security assessment (CASA).** Required for the restricted scope. After the scope review, Google emails instructions; the assessment is done by a Google-authorized lab, paid by Artifact, and renewed every year. Teleprompt has no backend, so there's no server in scope.
5. Answer Google's follow-up emails (they come to the developer contact, support@artifact.com).
