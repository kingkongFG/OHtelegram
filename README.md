# OHtelegram

**English** · [简体中文](README.zh-CN.md) · [Русский](README.ru.md) · [Français](README.fr.md)

> The translated READMEs still describe upstream Petrelgram 1.5.9 and do not
> cover the fork-specific changes documented below.

An open-source **unofficial Telegram client for HarmonyOS NEXT**, written in
ArkTS/ArkUI on top of [TDLib](https://core.telegram.org/tdlib), Telegram's own
client library, bridged through native N-API.

This repository is a **fork of [Petrelgram](https://github.com/miramira8295/Petrelgram)**
by *miramira8295*, taken at upstream version **1.5.9** (`versionCode 1003050`,
upstream commit `95b3629`). All of the client's foundations — the TDLib bridge,
the store layer, the original page set, the build and localization tooling —
come from that project. The sections below describe what this fork adds or
changes on top of it.

- Bundle name: `com.ohtelegram.client`
- Version: `1.5.9` (`versionCode 1003050`)
- License: [Apache License 2.0](LICENSE), unchanged from upstream

## What this fork changes

### Premium and Business surfaces

Two feature areas that upstream does not expose as pages:

- **Premium** — `store/PremiumApi.ets` reads `getPremiumState` / `getPremiumFeatures`
  and derives the subscription flag from `getMe().is_premium` rather than from
  displayed text; `pages/main/PremiumPage.ets` renders the entitlement list, the
  per-limit comparison (free vs. premium) and the server-provided price options.
  Field names are checked against `td_api.tl` and cross-checked against the
  strings shipped in the bundled `libtdjson.so`, and every read is
  existence-guarded, so an older TDLib that lacks a field loses one row instead
  of breaking the page. **No payment channel is wired up**: this client shows
  subscription state and pricing but deliberately does not fake a purchase flow.
- **Business** — `store/BusinessApi.ets` and `pages/main/BusinessPage.ets` cover
  `businessInfo`, greeting and away messages, quick replies, business chat links,
  opening hours and the account's connected bots. `util/openTelegramLink.ets`
  additionally resolves `internalLinkTypeBusinessChat` (`t.me/m/…`) into a
  `chat_id` before opening the conversation, falling back to a normal link when
  resolution fails.

Both entries are reachable from **Settings** (`pages/main/SettingsPage.ets`).

### Immersive light appearance system

The largest single change, spanning a build-time switch, a settings surface and
a rendering pipeline:

- `entry/src/main/module.json5` enables the system material gate
  (`ohos.arkui.UIMaterial.state = enable`). It is module-level metadata because
  the `app.json5` schema rejects it and placing it under the ability has no
  effect. Turning this off degrades every `systemMaterial` call and the UI falls
  back to the self-drawn path (blur + touch light), i.e. the whole layer can be
  removed at once.
- `util/touchGlow.ets` is the **single** entry point for the point-light effect:
  the system light is excited by the component's own touch event, its position is
  the touch point, and at most 12 simultaneous sources are allowed per component,
  so the surface is chosen by area (`chip` vs. larger surfaces) instead of
  attaching it to every child node. Chat rows, contact rows, the dock mini bar,
  the new-session banner, the composer and the search bars all adopt it.
- `pages/main/ImmersiveLightPage.ets` collects the appearance controls that were
  previously scattered across three cards of the chat settings page (overlay
  material thickness, surface glass, light level), adds system-material capability
  probing, and writes exactly the same settings keys as the existing consumers —
  it introduces no new setting semantics.
- `pages/main/BubbleStylePage.ets` + `util/bubbleStyle.ets` expand the old single
  corner-radius slider into three preset groups (5 shapes, 6 palettes, 7
  gradients) plus three immersive-light coverage scopes.
- `util/chatBubbleGradient.ets` is the only colour source for the night
  deep-blue background and the gradient fill of **1:1 plain-text** bubbles; call
  logs, system capsules, media/voice bars, quotes, link previews and stickers
  keep their flat colours and material logic. `util/bubbleTail.ets` follows the
  same fill colour. `pages/chat/ChatDoodleLayer.ets` draws a low-opacity line-art
  texture with Canvas, so no external art asset is added.
- `util/hdsPointLight.ets` restores the real point-light implementation behind a
  performance guard.

### Calls: floating window, ongoing notification, permissions, remote video

- `pages/call/FloatingCallWindow.ets` is an in-app floating call window. Its
  visibility is driven entirely by `CallSession.minimized` through AppStorage —
  there is no second copy of the state, which is what prevents a "window still
  visible, call already ended" ghost. `pages/Index.ets` stacks it above the page
  stack.
- `services/CallNotification.ets` posts an ongoing notification with a hang-up
  action while a call is connecting or active, so the user can end a call that is
  minimised or backgrounded. The action travels back as a common event into this
  process (`tdkit/Globals.ets` binds it to the current session).
- `util/callPermissions.ets` acquires microphone (and, for video, camera)
  permission **before** the call is created, instead of inside
  `CallPage.aboutToAppear` after tgcalls has already claimed the devices. This
  fixes the "first call requires a manual trip to Settings" case.
- Remote video is handed over between the full-screen page and the floating
  window via `CallSession.setRemoteSurface` / `clearRemoteSurfaceIf`: each side
  unbinds only when the currently bound surface id is still its own, so tearing
  one down no longer blanks the other.

### Stories management

`store/StoryManageApi.ets` adds the management half that the publishing path
(kept in `MyProfilePage`, not duplicated) did not cover: delete, edit
caption/cover, privacy, reactions, viewers, albums and stealth browsing.
`pages/story/StoryViewersPage.ets` lists viewers and forwards with
`next_offset` paging, and `pages/story/StoryViewerPage.ets` exposes the entry
points. The story store is opened at start-up from `MainTabBody` and then kept
current through `updateChatActiveStories`.

### Breakpoints and split view

Upstream already ships `util/layoutBreakpoint`; this fork does **not** add a
split-view module. What it does is route the new pages through the same
breakpoint rules and fix a state bug that shows up in multi-pane layouts:
`util/navBarReset.ets` re-evaluates whether a tab's nav bar counts as visible
when the tab is re-attached, because `onNavBarStateChange` only fires on change
and a stale `false` in AppStorage would hide the bottom dock permanently after a
full-page router jump.

### Memory pressure and cache governance

- `util/globalCacheTrim.ets` is a registry-based reclamation hub with budget
  levels. Previously `onBackground` called a single pixel-cache trim and left
  stickers, formula images, paragraphs, TGS text and covers untouched, so a
  low-memory device could still be killed with tens of MB of caches alive.
  Bubble-tail outlines, link-preview presentation, stickers, music covers, video
  posters, TGS unzip, math images, avatars, pixels and chat backgrounds all
  register a hook now.
- `entryability/EntryAbility.ets` subscribes to memory pressure through
  `EnvironmentCallback` on the application context (`UIAbility` has no
  `onMemoryLevel`; adding an `AbilityStage` just for the callback would split the
  start-up path). Backgrounding runs the critical level over all registered
  caches; returning to the foreground only restores budgets, it does not clear
  again.
- `util/tdlibTempCleanup.ets` sweeps TDLib's interrupted download fragments in
  `filesDir/tdlib_files/temp` at cold start (24 h normally, tightened to 1 h once
  the folder exceeds 200 MB), which neither TDLib nor the app's "clear cache"
  path would ever reclaim.
- `util/videoEngineFallback.ets` turns the full-screen player choice from a
  static setting into a fallback rule: AVPlayer keeps the HDR path, ijkplayer
  covers codecs AVPlayer rejects, and the switch happens per item instead of
  asking the user to find a settings toggle.
- `util/paragraphCache.ets` caches self-laid-out `Paragraph` objects for the plain
  text fast path, so scrolling a message in and out of the viewport no longer
  re-runs native text layout.

### Build, signing and native libraries

- `signingConfigs` in `build-profile.json5` is **empty** and no signing material
  is shipped. Generate a local debug certificate with DevEco Studio's
  auto-signing; nothing needs to be committed or shared.
- `entry/build-profile.json5` no longer declares `externalNativeOptions`, so
  hvigor does not build the C++ bridge during an app build; `libentry.so` is
  linked ahead of time and dropped into `entry/libs/arm64-v8a/`. A HAP build only
  needs those prebuilt libraries to be present — they are in the tree — while a
  *rebuild* of `libentry.so` also needs the static libraries below.
- The prebuilt native libraries **ship with the repository**: `libentry.so`,
  `libtdjson.so` and `libtgcalls_ohos.so` in `entry/libs/arm64-v8a/` (~52 MB
  together), `libvpx.a` / `librlottie.a` under `third_party/`, and the ijkplayer
  `.har` under `libs/`. A fresh clone therefore builds without running any
  fetch or build script; the scripts in `scripts/` are kept for rebuilding those
  artifacts from source.
- `hvigor/hvigor-config.json5` pins `hvigor-ohos-plugin` 6.26.4 explicitly, and
  the ijkplayer dependency resolves to the local
  `libs/ijkplayer-2.0.13-pg.10.har`.
- `services/UpdateChecker.ets` gets an `UPDATE_CHECK_ENABLED` switch, set to
  `false`: the upstream GitHub release feed is no longer valid, so the checker
  neither restores a cached "update available" state nor issues a request, and
  the stale badge is cleared.
- Branding: bundle name `com.ohtelegram.client`, vendor `ohtelegram`, plus the log
  file names, crash watcher names and the download folder name that used to carry
  the upstream package name.

### Localization keys

158 new keys were added to `entry/src/main/resources/base/element/string.json`
for the surfaces above (Premium/Business, immersive light, call states, story
management). Theme/colour values are computed in code rather than stored in
resources, because a bare `%` inside a resource value is interpreted as a format
placeholder. The other 19 locales fall back to `base` for the new keys; the
existing `i18n-check.mjs` gate reports them as missing until they are translated.

## Features

Inherited from upstream, unchanged unless noted above:

- **Accounts** — phone login with 2FA, multiple accounts, switching, sign-out
- **Chats** — folders, archive, unread badges, live connection status
- **Messages** — rich text, photos, albums, video, files, stickers (WEBP / TGS /
  WEBM), custom emoji, replies, forwards, reactions, comment threads, pinned
  messages, scheduled messages, multi-select
- **Composer** — mentions and command autocomplete, media, files, voice, music,
  location, contacts, polls, dice
- **Calls** — end-to-end encrypted 1:1 voice and video via tgcalls
- **Group calls & live streams** — multi-party voice, camera and screen sharing,
  channel broadcasts, in-app floating window
- **Topics & Stories** — forum topic lists and per-topic message streams;
  full-screen story viewer
- **Search** — global search across 11 categories
- **Profiles** — user, bot, group and channel pages; avatar, bio and username
  editing; QR business card
- **Settings** — privacy and security, notifications, storage, sessions and
  devices, chat folders, battery saver, dark mode

## Layout

```
AppScope/            app-level config (bundle name, icon)
entry/src/main/ets/
  tdkit/             TDLib N-API bridge, client, auth service
  store/             immutable stores + subscriptions (chats, messages, …)
                     plus the Premium / Business / story-management data layers
  pages/             ArkUI pages (login, chat list, chat, profile, search …)
                     main/ also holds PremiumPage, BusinessPage, BubbleStylePage,
                     ImmersiveLightPage; call/ holds the floating call window
  services/          media streaming, live-stream background tasks, audio,
                     ongoing call notification
  util/              parsing and formatting (rich text, albums, dates …),
                     appearance presets, the cache-trim hub, temp cleanup
entry/src/main/cpp/  native bridge (libentry.so → libtdjson.so / libtgcalls_ohos.so /
                     libvpx.a / librlottie.a)
entry/src/test/      unit tests (run via scripts/run-local-tests.sh)
libs/                ijkplayer-2.0.13-pg.10.har (referenced by oh-package.json5)
entry/libs/arm64-v8a/ prebuilt libentry.so / libtdjson.so / libtgcalls_ohos.so
third_party/         libvpx-ohos/ and rlottie-ohos/ static libraries + headers
scripts/             optional rebuild scripts for TDLib, tgcalls, libvpx,
                     rlottie and ijkplayer; i18n tooling; local test gate
```

## Building

### Requirements

- **DevEco Studio 6.0+** with its bundled OpenHarmony SDK/NDK
- A HarmonyOS NEXT device or emulator (arm64-v8a)
- A Huawei developer account, needed only for the automatic signing step

Nothing else has to be installed before building: the native libraries and the
ijkplayer package are already in the tree.

### 1. Native libraries (already in the repository)

Everything `libentry.so` links against ships with the repository, so a fresh
clone needs no download and no compilation:

| Path | Contents |
| --- | --- |
| `entry/libs/arm64-v8a/` | `libentry.so` (N-API bridge), `libtdjson.so` (~33 MB), `libtgcalls_ohos.so` (~18 MB) |
| `third_party/libvpx-ohos/` | `libvpx.a` + headers |
| `third_party/rlottie-ohos/` | `librlottie.a` + headers |
| `libs/` | `ijkplayer-2.0.13-pg.10.har`, referenced by `oh-package.json5` |

Consequences:

- You do **not** need to run `scripts/fetch-libs.sh`, `scripts/fetch-tdlib.sh`,
  `scripts/fetch-ijkplayer.sh`, `scripts/build-tdlib.sh`,
  `scripts/build-tgcalls-ohos.sh`, `scripts/build-libvpx-ohos.sh` or
  `scripts/build-rlottie-ohos.sh`. They are kept only for rebuilding the
  artifacts from source, which needs an OHOS NDK toolchain (clang, cmake, ninja,
  gperf, patchelf) and a long first WebRTC build.
- `entry/build-profile.json5` declares no `externalNativeOptions`, so hvigor
  never compiles the C++ bridge: the prebuilt `libentry.so` is packaged as is.
  Rebuilding it is a separate, rarely needed step, described at the end of this
  section.
- For reference: TDLib 1.8.65, tgcalls as pinned in
  [`scripts/tgcalls/README.md`](scripts/tgcalls/README.md), ijkplayer
  `2.0.13-pg.10` (the async-release patch is
  `scripts/ijkplayer-pg10-async-release.patch`).

### 2. Telegram API credentials (register your own)

This repository ships **no** `api_id`/`api_hash`, and no script that generates,
packs or obfuscates them. TDLib cannot log in without a pair you own:

1. Register an application at <https://my.telegram.org/apps>. The page returns an
   `api_id` (a number) and an `api_hash` (32 hex characters).
2. Copy `entry/src/main/ets/tdkit/ApiCredentials.template.ets` to
   `ApiCredentials.ets` in the same directory.
3. Fill in the two plain-text constants of that copy:

   ```ts
   export const apiId: number = 1234567;                              // your api_id
   export const apiHash: string = '0123456789abcdef0123456789abcdef'; // your api_hash
   ```

   The same file also carries four optional fields — `pushRelayBase`,
   `pushRelayToken`, `crashReportBase`, `crashReportToken` — which stay empty
   unless you run your own push relay or crash collector. Empty values simply
   hide those features; nothing else depends on them.
4. Build. No other file reads those values, and no build step needs network
   access.

`**/ApiCredentials.ets` is listed in `.gitignore`, so the filled-in copy cannot
be committed by accident — **never commit real credentials**, and revoke and
re-register immediately if they leak. Keep them out of issues, screenshots and
logs too: they identify your application to Telegram, not your account, but they
are not public.

### 3. Signing

`signingConfigs` in `build-profile.json5` is empty, and the repository contains no
certificate, keystore or provisioning profile:

1. Open the project in DevEco Studio.
2. Go to **File > Project Structure > Signing Configs** and tick
   **Automatically generate signature** (HarmonyOS auto-signing; the IDE must be
   signed in with a Huawei developer account).
3. Let DevEco Studio generate the debug certificate and profile for
   `com.ohtelegram.client`. They live in your user profile, outside the
   repository.

No HAP or APP package is kept in the repository either: build output stays under
`entry/build/`, which is gitignored.

The upstream sources shipped this file with absolute paths to a local
certificate, keystore and provisioning profile, plus the matching keystore
password, checked in as plain text. This fork removed all of it. If you build
from upstream, treat those values as compromised: generate your own certificate
and never reuse a keystore or password that has been published.

### 4. Build and run

The whole flow is four steps in DevEco Studio:

1. **Open the project** — `File > Open`, pick the repository root (the folder
   holding `build-profile.json5`), and let the sync that DevEco Studio starts on
   open finish (`ohpm install` runs as part of it).
2. **Configure signing** as described in step 3.
3. **Build the HAP** — `Build > Build Hap(s)/APP(s) > Build Hap(s)`, or
   `hvigorw assembleHap --no-daemon` in a terminal where `hvigorw` is on `PATH`.
   The output lands in `entry/build/default/outputs/default/`.
4. **Run on the device** — connect a HarmonyOS NEXT device with USB debugging
   enabled (or start an emulator), select it in the device selector and press
   **Run**. The first launch asks for a phone number and the login code Telegram
   sends; TDLib handles the rest.

Because `externalNativeOptions` is not declared, this packages the prebuilt
`libentry.so` from `entry/libs/arm64-v8a/` — it does not compile the bridge. No
`fetch-*` or `build-*` script has to run before, during or after the build.

Optional, only after changing the C++ sources: add an `externalNativeOptions`
entry pointing at `entry/src/main/cpp` with `abiFilters: ["arm64-v8a"]` back into
`entry/build-profile.json5` (the CMake project and the `entry` shared target are
still in the tree, `project(Petrelgram)`), build once so that cmake/ninja produce
`libentry.so`, copy it into `entry/libs/arm64-v8a/`, and remove the option again.
Keeping the bridge out of the app build is deliberate: it is a few thousand lines
of C++ that changes rarely, while the HAP build runs many times a day.

Optional sanity check, for contributors only (needs Node.js; not part of the app
build):

```bash
./scripts/run-local-tests.sh    # must print "LOCAL TESTS: PASS"
```

The script runs the i18n check before the unit tests — a static check that
answers in a second should not sit behind a two-minute test build.

## Localization

All UI copy lives in resource files. The source language (Simplified Chinese) is
`entry/src/main/resources/base/element/string.json`; translations go in
language-qualified directories (`en_US/element/string.json` and so on), plurals
in `element/plural.json`. The system matches the device language and falls back
to `base` — which is what the 158 keys added by this fork currently rely on in
the locales that have not been translated yet.

**`$r()` vs `str()`.** Anything a component renders uses `$r('app.string.x')`:
it is a `Resource`, re-resolved by ArkUI on configuration change, so switching
language takes effect immediately. `str('x')` returns a plain string fixed at
build time — use it only where a `string` is genuinely required: `string`-typed
`@State`, model fields, comparisons, `.join()`, and non-UI code. When a
`@Builder` parameter causes a type conflict, widen it to `ResourceStr` rather
than reverting the call site to `str()`.

**Module-level `const` cannot hold copy.** Constants are built on first import,
before the string source is ready, freezing the language at that moment. Use a
function (`fallbackCountries()`, not `FALLBACK_COUNTRIES`).

**Never match on displayed text.** `label.substring(0, 2)` or
`text.includes('Retry')` breaks the moment the language changes; branch on
structured fields instead.

Diagnostic strings that only reach `console.*` are not translated; mark them
with `// i18n-exempt: <reason>`.

```bash
node scripts/i18n-extract.mjs               # remaining hardcoded copy, by domain
node scripts/i18n-extract.mjs --domain util # details and key suggestions
node scripts/i18n-lit.mjs <file>            # literals with line numbers
node scripts/i18n-check.mjs                 # the gate (also in run-local-tests.sh)
```

`i18n-check.mjs` checks five things: every key referenced in code exists in
`base`; every key in `base` is referenced somewhere; **no `${` template source
survives in a resource value, and placeholder numbering matches across
languages**; no orphan keys outside `base` and which entries each language is
missing; **no Chinese literals remain in directories already covered by the
gate**.

`MIGRATED` in `scripts/i18n-config.mjs` now covers every source directory — add
new directories to it, or the gate will quietly skip them. Key naming is
`<domain>_<component>_<meaning>`, e.g. `chat_forward_title`.

## Status and disclaimer

- Under active development; the interface aims to stay close to the official
  Android client.
- This is an **unofficial** client and an unofficial fork. Use your own API
  credentials and comply with the
  [Telegram API Terms of Service](https://core.telegram.org/api/terms).
- No application-internal purchase flow exists: the Premium and Business screens
  display server-provided state and prices only. Nothing here is a licence to
  bypass a subscription.
- Stranger search follows Telegram/TDLib server-side discoverability rules: it
  generally finds only users with a public username or otherwise in the server's
  search scope, and cannot be used to enumerate arbitrary phone numbers.
- Upstream project and community: [miramira8295/Petrelgram](https://github.com/miramira8295/Petrelgram).

## License

[Apache License 2.0](LICENSE)

Copyright and attribution for the original work remain with the upstream
Petrelgram project and its contributors. This fork keeps the same licence; see
`LICENSE` for the full text.
