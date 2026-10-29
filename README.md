# Raven for macOS

The native macOS app of [Raven](https://raven-messager.com), a private messenger with no central
server. It is written in SwiftUI and talks to Raven only through the engine `raven-client` (one C
function, JSON in and out; the contract is `core/desktop/api/API.md`). It follows the shared design
in `core/desktop/design/` (`DESIGN.md`, `tokens.json`, `strings.en.json`) and is drawn in the
**Calm** design (see "Calm" below).

The engine, the background program `raven-node`, the protocol and the shared design live in the
[`raven-core`](https://github.com/Raven-ASHCO/raven-core) repository, included here as a git
submodule at `core/`.

## Status

**In development.** There is no signed or notarised build and nothing to download yet. The app
uses whatever the engine allows: in a release engine only direct messaging on the local network is
on, and every other way to reach friends is a lab feature that stays off (see `core/README.md`).
Without the engine (a plain `swift build`) the app shows the engine-missing screen. **MockRaven**,
an in-memory engine that follows the contract and replays demo events, is compiled only into debug
and demo builds and runs only when asked (`RAVEN_DEMO=1`).

## Requirements

- macOS 13 or later.
- A Swift 5.9+ toolchain. The Command Line Tools are enough (no Xcode needed). No third-party
  packages.
- For the engine: Rust ([rustup](https://rustup.rs); `raven-core` CI uses 1.98.0) with the target
  of this Mac (`aarch64-apple-darwin` on Apple silicon). The scripts install nothing.

## Get the code

```sh
git clone --recurse-submodules https://github.com/Raven-ASHCO/raven-macos.git
cd raven-macos
# or, in an existing clone:
git submodule update --init
```

## Build, run, test

```sh
swift build                      # debug build without the engine: the engine-missing screen
RAVEN_DEMO=1 swift run Raven     # the demo on MockRaven: welcome and setup first, then the demo friends
swift test                       # unit tests (swift-testing); the engine tests are not built
swift run RavenSnapshots [dir]   # PNGs of every main screen, light and dark, 1200 x 760 (default dir: .build/snapshots)

scripts/build-engine.sh dev      # cargo build -p raven-client -p raven-node (core/node/target/debug)
RAVEN_ENGINE=dev swift test      # also the engine tests (EngineTests.swift), on a temporary profile
scripts/build-engine.sh          # the release engine (core/node/target/release)
RAVEN_ENGINE=1 swift build       # link it
```

### Linking the engine

`Package.swift` links the engine only when the environment asks for it, so the package builds and
tests on a machine without Rust:

| Variable (at build time) | Engine linked |
|---|---|
| unset | none: `MissingEngine` answers every call with `NOT_INITIALIZED` and the engine-missing text |
| `RAVEN_ENGINE=1` (or `release`) | `core/node/target/release/libraven_client.a` |
| `RAVEN_ENGINE=dev` | `core/node/target/debug/libraven_client.a`, the engine's debug build |
| `RAVEN_ENGINE_LIB=/path/libraven_client.a` | that file |

With an engine, Package.swift adds the system-library target `CRavenClient`
(`Sources/CRavenClient/module.modulemap`, which points at `core/node/crates/raven-client/include/raven_client.h`;
no copy of the header), makes RavenUI and the tests depend on it, defines `RAVEN_ENGINE`, and links
the static library by its full path (`-Xlinker <path>`: cargo writes `libraven_client.dylib` next to
it, which `-lraven_client` would pick instead) plus what the engine needs from the system:
`-framework Security -framework CoreFoundation -liconv` (from `cargo rustc -p raven-client --release
--lib --crate-type staticlib -- --print native-static-libs`; libSystem, libc and libm come with every
link). SwiftPM re-reads the manifest when these variables change, so switching between them in one
build folder works (it rebuilds RavenUI).

`scripts/build-engine.sh [release|dev]` runs `cargo build -p raven-client -p raven-node` (with
`--release` for release) in `core/node/`, with `MACOSX_DEPLOYMENT_TARGET=13.0`, the app's minimum (without it
the SQLCipher C code is built for the SDK's macOS 27). It builds for this Mac's architecture only. The
**dev** engine exists for tests and smoke runs: a release engine refuses the file-backed secret stores
(`RAVEN_*_BACKEND=locked-file`), so on a test profile it can only report the profile as unreadable.

### Which engine runs

`EngineFactory.makeDefault()`: a demo build (`-DRAVEN_MOCK`) runs on MockRaven; a debug build runs on
MockRaven only when started with `RAVEN_DEMO=1`; otherwise the app runs on `RavenClientEngine` when the
engine is linked, else on `MissingEngine`. A release build never picks the mock unless it was built as
the demo. The engine works on the profile the CLI uses (`RAVEN_DATA_DIR`, else `~/.raven`), read on
its first call: **a build with the engine on your own profile is the real thing** (Keychain, your
contacts). To try it safely, point `RAVEN_DATA_DIR` at a throwaway folder and use the dev engine with
the file-backed stores.

Environment variables for the demo (`RAVEN_DEMO=1 swift run Raven`, debug builds only):

| Variable | Effect |
|---|---|
| `RAVEN_DEMO=1` | run on MockRaven |
| `RAVEN_MOCK_STATE=ready` | skip welcome and setup; start with the demo profile |
| `RAVEN_MOCK_STATE=locked` | start on the Locked screen (Unlock answers `NOT_AVAILABLE_YET` until the privacy pack) |
| `RAVEN_MOCK_DEMO=0` | no demo event stream (only the heartbeat and what you do) |
| `RAVEN_MOCK_NETWORK=lab` | the network answers of a developer build with lab switches (see "Network screens") |

At start the app logs one line (Console.app, subsystem `io.github.raven-ashco.Raven`, category
`engine`): the engine, its build and version, and the profile state it reported, e.g. `engine
RavenClientEngine (release, 0.1.0): profile new`. Nothing about friends, messages or keys.

`RavenSnapshots` renders with SwiftUI's `ImageRenderer`: it opens no window, starts no `raven-node`
and never calls the engine (MockRaven and `MissingEngine` only).

The running app has its own snapshot hook, in debug builds only: started with
`RAVEN_DEBUG_SNAPSHOT_DIR=<folder>`, it renders the Network page, the consent sheet for carrying
mail for friends and the Check network page (light and dark) from its live model and engine into that
folder, prints the files and quits. It never asks the router, never sends `agreed` and starts no
raven-node. A new profile stays on the welcome screen unless `RAVEN_DEBUG_SNAPSHOT_SETUP=1` and the
profile is a throwaway one (`RAVEN_DATA_DIR`, `RAVEN_ALLOW_EPHEMERAL_DATA_DIR=1`, the file-backed
identity store): then it is set up first (receiving off). A run on the dev engine:

```sh
P=$(mktemp -d "${TMPDIR}rvm.XXXXXX"); mkdir -m 700 "$P/p"
RAVEN_DATA_DIR="$P/p" RAVEN_IDENTITY_BACKEND=locked-file RAVEN_SESSION_BACKEND=locked-file \
RAVEN_PREKEY_BACKEND=locked-file RAVEN_CHAT_HISTORY_BACKEND=locked-file RAVEN_ALLOW_EPHEMERAL_DATA_DIR=1 \
RAVEN_SERVICE_LAN_LISTEN=127.0.0.1:0 RAVEN_LAB_TEST_A=1 RAVEN_LAB_LOCAL_PROTECTION=1 \
RAVEN_DEBUG_SNAPSHOT_DIR=/path/to/shots RAVEN_DEBUG_SNAPSHOT_SETUP=1 RAVEN_ENGINE=dev swift run Raven
rm -rf "$P"
```

### Engine tests

`Tests/RavenUITests/EngineTests.swift` is compiled only with an engine. Before the first call it
points the engine at a new temporary folder with the file-backed stores (`RAVEN_DATA_DIR`,
`RAVEN_{IDENTITY,SESSION,PREKEY,CHAT_HISTORY}_BACKEND=locked-file`, `RAVEN_ALLOW_EPHEMERAL_DATA_DIR=1`;
the folder is removed at exit), so it never touches `~/.raven` or the Keychain, and it never starts
raven-node (`receive` stays off). With `RAVEN_ENGINE=dev`: `profile.state` `new` and the welcome
screen, `app.info`, `privacy.state`, `privacy.unlock` (answers as `profile.state`) and the other
privacy ops (`NOT_AVAILABLE_YET`), settings kept in memory
before the identity, `identity.create` (10 words on Raven's list whose check word fits, the old code),
`profile.state` `ready`, `identity.me`, `card.make` (with and without an address), the settings
round-trip (a UTF-8 name, `desktop_settings.json`, `BAD_REQUEST`), `node.status`, `events.poll` (and
`reset` for a seq from before the engine), the app opening the ready profile; `verify.word_hint`; the
C boundary (NULL request, unknown op, bad JSON); the network ops (`network.status` with every way,
a held way refused, the bridge/store/relay flags, `network.check`, `security.status`, `lock.state`,
`updates.status`) and the Network page's model reading `network.status` from the profile
(`theNetworkPageReadsTheEngine`: every way named and in a state, LAN direct switchable, the lab
banner following the `RAVEN_LAB_*` switches the engine sees). With `RAVEN_ENGINE=1` (the release
engine) the profile steps are skipped and a test checks that the release engine refuses the
file-backed stores.

## App bundle and DMG

```sh
scripts/make-app.sh [out-dir]                  # out-dir/Raven.app on the engine, arm64 (default: dist/)
RAVEN_DEMO=1 scripts/make-app.sh [out-dir]     # the demo on MockRaven, universal (arm64 + x86_64)
scripts/make-dmg.sh [Raven.app] [out.dmg]      # unsigned developer DMG: Raven.app + Applications link
```

- **Engine.** `make-app.sh` runs `scripts/build-engine.sh` (release), builds the app with
  `RAVEN_ENGINE=1`, and copies `raven-node` to `Contents/MacOS/raven-node`: the engine starts the
  `raven-node` next to the app's executable (`RAVEN_NODE_BIN` overrides it; then the CLI's lookup).
  `raven-node` is signed ad hoc before the bundle. `RAVEN_ENGINE=dev scripts/make-app.sh` links the
  dev engine and its raven-node instead, for smoke runs on a test profile only (never ship it).
- **arm64 only with the engine.** The engine is built with the Rust targets already installed, which
  here is `aarch64-apple-darwin` only (the x86_64 target is not installed and the scripts install
  nothing). An Intel slice without the engine and raven-node could only show the engine-missing
  screen, so the engine app is arm64 only (no `LSMinimumSystemVersionByArchitecture`; macOS refuses
  to open it on an Intel Mac). A universal engine app needs `x86_64-apple-darwin`, an x86_64 engine
  and raven-node joined with `lipo`, and the Intel slice linked against the x86_64 library.

- `make-app.sh` builds the release binary (the demo: for Apple silicon and for Intel, joined with
  `lipo`), writes `Info.plist` (bundle id `io.github.raven-ashco.Raven`, the macOS spelling
  of the shared app id in `core/desktop/README.md`, `LSUIElement` false, macOS 13 minimum,
  `NSLocalNetworkUsageDescription` taken from `setup.receive.body`), draws `Raven.icns`, copies the
  resource bundle into `Contents/Resources`, and signs the bundle ad hoc (`codesign --sign -`;
  `RAVEN_SIGN=0` skips it). This is not a Developer ID signature and not notarised.
- **Universal demo build.** The Command Line Tools build x86_64 (`swift build -c release --arch x86_64`
  works), but for the macOS 27 SDK they ship Swift's back-deployment libraries
  (`libswiftCompatibility*.a`, among them `CompatibilityPacks`) for arm64 only, so an x86_64 build for
  macOS 13 links without them (`ld: warning: ignoring file ... missing arch 'x86_64'`). The Intel slice
  is therefore built for macOS 14 (`--triple x86_64-apple-macosx14.0`, whose Swift runtime needs none
  of them) in its own scratch path (`.build/x86_64`), and `LSMinimumSystemVersionByArchitecture` says
  arm64 13.0, x86_64 14.0, so Finder explains the requirement on an Intel Mac with macOS 13. Apple
  silicon keeps macOS 13. `RAVEN_UNIVERSAL=0` builds arm64 only; if the x86_64 build fails, the script
  says so and makes an arm64 app.
- **Icon.** `scripts/make-icon.swift` (CoreGraphics and ImageIO, run with `swift`) draws every size of the
  iconset from `raven-mark-1024.png` and `tokens.json`: an 824 px tile on the 1024 px canvas (the macOS
  icon grid) with continuous corners, a hairline `border` edge and a soft shadow, filled from `surface`
  (top) to `background` (bottom), with the mark in `textPrimary`, made solid (the design file draws it
  as a 40% grey) and centred at 66% of the tile. `iconutil` turns the iconset into `Raven.icns`.
- A release build has no mock. For a clickable demo bundle use `RAVEN_DEMO=1 scripts/make-app.sh`
  (adds `-DRAVEN_MOCK`; no engine, no raven-node).
- `make-dmg.sh` stages `Raven.app` with a symlink to `/Applications` and runs `hdiutil create`
  (UDZO) and `hdiutil verify`; it never mounts or opens the image. `--layout` as a third argument
  also sets the Finder window (background with the arrow and "Drag Raven to Applications", icon
  positions); that mounts the image and scripts Finder, so it opens a Finder window. The background
  is `dmg-background.png` from `RavenSnapshots`.

## Layout

```
Package.swift
Sources/
  CRavenClient/module.modulemap   raven_client.h as a Swift module (used only with the engine)
  Raven/RavenApp.swift            App: Window, Settings, MenuBarExtra, commands, quit handling
  RavenSnapshots/                 PNG renderer (debug only)
  RavenUI/
    Engine/   RavenEngine.swift   protocol `call(op:args:)`, `EngineQueue`, envelope v1, typed wrappers (sanitising)
              Models.swift        API.md types (unknown fields ignored, unknown enum values tolerated)
              MockRaven.swift     in-memory engine, demo stream, word list + check word (debug only)
              RavenClientEngine.swift  raven_call/raven_free (with the engine), MissingEngine, EngineFactory
    State/    AppModel.swift      screen state; turns events into texts and motion triggers; pages, Lock v2
              NetworkModel.swift  the Network screens: network.status/set, consent, restart, check, routes,
                                  security, updates
              Display.swift       text decisions (tick text, status line, heartbeat, way states, path chips), unit-tested
    Support/  Strings.swift       `Str`: every key the app uses (all in strings.en.json)
              TimeText.swift      `{when}`, `{left}`, `{time}`, `{secs}` from the `time.*` texts
              AppIdentity.swift   the bundle id `io.github.raven-ashco.Raven`
              Theme.swift         tokens.json -> palette (light/dark), sizes, durations
              Sanitizer.swift     strips control, bidi, zero-width and invisible characters
              WordInput.swift     splitting typed security words (Persian/Arabic-Indic digits ignored), old-code key and groups
              ViewState.swift     `@ViewState` (see "Notes")
    Components/, Views/           the screens (Network: NetworkPage, NetworkSheets, CheckNetworkPage,
                                  FriendRoutesSheet, SecurityPages; Calm.swift; GroupViews.swift;
                                  SettingsView.swift: the seven Settings sections)
    Snapshot/SnapshotCatalog.swift  the snapshot scenes (debug only)
             DebugSnapshotHook.swift  RAVEN_DEBUG_SNAPSHOT_DIR for the running app (debug only)
    Resources/                    copies of strings.en.json, tokens.json, the word list and the mark
Tests/RavenUITests/               MockRaven, events and motion triggers, words, old code, privacy, strings,
                                  time texts, polling, threading, app id, sanitiser, engine extras,
                                  NetworkModelTests (the Network screens on MockRaven),
                                  EngineTests.swift (the real engine; only with RAVEN_ENGINE)
scripts/  build-engine.sh, make-app.sh, make-icon.swift, make-dmg.sh, sync-design.sh
```

`Resources/` holds copies of the design files (SwiftPM resources must live inside the target). After
changing anything in `core/desktop/design/`, run `scripts/sync-design.sh`; `DesignSyncTests` fails when the
copies drift.

## Texts

Every text comes from `core/desktop/design/strings.en.json` through `tr(.key)`; `Str` lists every key the app
uses and `StringsTests` checks that each one exists (there are no fallback texts). Placed on purpose:

- Menu bar friend lines join existing texts with " · " ("Ali · In touch just now", "Mina · 1 waiting ·
  until Wed 12:05"); a friend with unread messages shows `home.newFrom` ("1 new from Rena").
- The paste field of Add a friend uses `add.step2` ("Paste theirs") as its placeholder, the name field
  `add.name.title`; copying a message reuses `add.share.copy`.
- `Info.plist`'s `NSLocalNetworkUsageDescription` (the macOS Local Network prompt) uses
  `setup.receive.body`.
- Engine error messages: `MockRaven` and `MissingEngine` use the `error.*` texts, the wording
  `raven-client` uses. Texts the engine sends (error messages, a stop `note`) are shown as sent,
  after sanitising.

## What is mocked

Everything behind `RavenEngine`. `MockRaven` (compiled only with `DEBUG` or `-DRAVEN_MOCK`):

- implements every operation of API.md in memory, through the same JSON envelope as `raven_call`
  (`handle(_ requestJSON:) -> String`), with the error codes and plain-English messages (`error.*`;
  an unknown operation or bad arguments give `BAD_REQUEST`);
- the demo identity (`turtle frog bread wolf paper laptop funnel mango honey wagon`, old code
  `If4x-36FU-omFi`, the reference vector of the security-words prototype) and the friends Ali
  (verified, in touch), Mina (one message waiting until a deadline) and Rena (not verified);
- the demo event stream, started by the first `events.poll` after setup: `status_ok` every 2 s;
  incoming from Ali; Rena in touch with a message; retry on Mina's waiting message; a demo send to
  Ali (`send_started` -> `state: sent` -> `receipt`); Mina back in touch and her waiting message
  delivered. Only the event kinds of API.md are used;
- security words with Raven's 256-word list and the GF(2^8) check word (a port of
  `security_words.py`): `verify.word_hint` completes after 3 letters, `verify.check_words` answers
  match / typo / mismatch and never returns a friend's words;
- `verify.check_old_code`: Rena's old code is `Tq7m-29Xa-hKe4` (the same demo value in all three
  apps); other friends have none. Spaces, separators and zero-width characters are ignored and
  Persian, Arabic-Indic and full-width digits folded; letters are case-sensitive. The answer is only
  match or mismatch, and a match verifies the friend as the words do;
- `privacy.state` answers `available: false`; `privacy.lock`, `unlock`, `encrypt` and `erase` answer
  `NOT_AVAILABLE_YET` (an `erase` without `confirm: "erase"` gives `BAD_REQUEST`). The engine answers
  the same for `lock`, `encrypt` and `erase`; its `unlock` clears a `raven lock` and answers as
  `profile.state`;
- node start/stop (listening comes up 1.5 s after start; `node.stop` says `stopped`, or `managed` for
  a raven-node a login service runs, see `runNodeAsLoginService`) and settings;
- the network ops as a release build by default (LAN direct on, every other way `preview`, a held way
  refused with `NOT_AVAILABLE_YET`), or with `network: .lab` (`RAVEN_MOCK_NETWORK=lab`) as a developer
  build with `MockRaven.labSwitches`: Internet direct, port mapping and friend custody `off`, p2p
  and route hints `lab` (p2p running with one relay), handoff `off`, Bluetooth nearby
  `not_on_this_os`; `CONSENT_NEEDED` without `agreed`; `restart_needed` for Internet, p2p, port
  mapping and the proxy while raven-node runs; Lock v2 with the passphrase `MockRaven.labPassphrase`;
  one security notice; updates status; Ali's question came over a relay and Mina's waiting message
  waits with a friend (path chips).

Without the engine, `MissingEngine` answers every call with `NOT_INITIALIZED` and a plain-English
message (screenshot `25-release-without-engine`).

## Network screens

Every way Raven connects (`core/desktop/api/NETWORK_PARITY.md`), from the engine's network ops. The sidebar has
Network, Check network, Security and Updates under the friends (also the Network menu, Cmd-Opt-1 to
4); picking a friend brings the chat back. `NetworkModel` holds their state; a switch always shows the
engine's answer, never a guess.

- **Network** (`network.status`): one row per way and per protection with its state chip (On, Off,
  Preview, Lab only, Not on this computer), the plain reason, "In use now" where raven-node says,
  Details (`detail`), and a switch where `network.set` changes the way (`can_set`). The switch can be
  used unless the way is held and off, or not on this computer; the proxy has Automatic / Off / an
  address instead. Under the rows: this computer's port and listening addresses, LAN for a while
  ("Turn on for…", `lan_for`), the router's answer and NAT-PMP/PCP state, relays in use (added by
  you or lent by a friend), p2p addresses, Bluetooth nearby rows, who carries mail both ways (carry
  mail for friends, messages held, letters, the relay you lend), the bridge/store/relay flags with
  the engine's honest effects, and hide my IP. After a change, "What changed" shows each change's
  `effect`. A refusal (`NOT_AVAILABLE_YET`, ...) appears under the row that was changed.
- **Lab switches on**: in a developer build whose engine lists `RAVEN_LAB_*` switches
  (`lab_switches`, build `dev`), a banner on the Network page and a strip above the other pages. A
  release engine reads and lists none, so a release build never shows it.
- **Consent sheets** for carry mail for friends, let friends carry your mail and pass mail on
  between friends: exactly the three the engine answers with `CONSENT_NEEDED` (API.md, the consent
  rule). Each says what it does, what it costs, what others can and can't see, and the engine's own
  text (`texts`). Turning one on opens the sheet and sends nothing; "I agree, turn it on" sends the
  setting with `agreed: true`; "Not now" sends nothing. A `CONSENT_NEEDED` from the engine opens the
  same sheet. Relay for friends and the bridge/store/relay flags have no sheet: their honest effect
  stands beside the switch (`network.relayForFriends.effect`, the engine's `help.effects`).
- **Restart the background program** when `network.set` says `restart_needed`: Restart now is
  `node.stop` then `node.start`. A raven-node a login service runs is left running (`stop:
  managed`) and the engine's note says how to restart it; nothing is started then. Later keeps the
  change for the next start.
- **Check network** (`network.check`): the doctor's summary and next step, the network lines with
  Raven's plain sentence where it has one, and "Ask the router" (`router: true`, read-only, a few
  seconds) with the macOS Local Network note.
- **A friend's routes** (Routes in the chat header; `contacts.routes` / `contacts.set_routes`): saved
  routes with their state and Remove, an Internet (`host:port`) or p2p route (with relays) to add,
  what the friend told this computer (route hints, its network ID and whether it is proven), hide this
  computer's IP from them, who carries their mail (named, listed, coverage) and up to two verified
  mail friends. Never the friend's security words or old code.
- **Path chip** under every message that has a path (`path_kind`: LAN, Internet, p2p, Relay, Hole
  punched, 443, Nearby, Friend, Handoff, Letter; an unknown kind shows the engine's path words).
- **Security** (`security.status`, read-only: notices with what Raven did and what to do, the
  background program's counts) with **Lock while running** (`lock.state`; Lock now where the running
  raven-node serves Lock v2). Lock now in the menu bar and the menu uses Lock v2 when it is served,
  else the privacy pack's lock. A locked raven-node opens the app on the locked screen, which asks
  for the Raven passphrase when the profile has one (it goes only to raven-node; `PASSPHRASE_WRONG`,
  `PASSPHRASE_NEEDED` and `UNLOCK_WAIT` are shown as the engine says them).
- **Updates** (`updates.status`, read-only): the status lines and what is ready; installing stays in
  the terminal (`raven update install`).

Motion: nothing new moves on its own. A spinner shows only while a check, the router question or a
restart is running, and stands still with reduced motion; a switch moves only when the engine's answer
comes back. Snapshots `31`-`40` show the screens (release and lab mock), the running app's hook the same on
the real engine.

## Calm

The design the owner chose on 2026-10-28 (`core/desktop/design/DESIGN.md`, "Calm at a glance"; tokens version 2).
`Components/Calm.swift` holds the shared pieces (cards and grouped rows, segmented control, radio rows,
state chips, path chips with their colours and icons, the status icons, the group ring, the toast
pill); `Controls.swift` the Calm buttons, switch (`RSwitchStyle`, and `RSwitch` for rows that draw
their own title) and fields. `Theme` reads every token, including the motion curves (`Theme.curve`,
SwiftUI timing curves with the prototype's overshoot) and springs.

- **Window:** sidebar (mark and heartbeat, You, search, FRIENDS, GROUPS, Add a friend / New group, and
  Network, Security words, Security, Settings at the bottom) and the right side: a chat, a group, a
  page, or Settings. Check network opens from the Network page; Updates is a Settings section (and
  stays in the Network menu, Cmd-Opt-4).
- **Settings live in the main window** (Cmd-, opens them there; there is no separate Settings
  window): General, Appearance, Privacy, Lock, Network, Updates, About. Appearance's Theme
  (System/Light/Dark) and Show technical details are this app's own preferences (UserDefaults
  `calm.theme`, `calm.showTechnicalDetails`); everything else is the engine's (`settings.*`,
  `privacy.state`, `lock.state`, `network.*`, `updates.status`). "Start Raven when I log in", "Lock
  when idle" and "Share my network address in my invite" from the prototype are left out: the engine
  reports none of them (and cards carry no address).
- **Motion, all from real events or your own action:** your bubble lifts out of the composer
  (`AppModel.liftIDs`, set when `messages.send` / `groups.send` returns), the delivered check fills
  and pops and the path chip slides in on the signed receipt (`deliveredPops`), a group message's
  arcs take their colour as receipts come (`group_changed`), the radar on the Network page and the
  heartbeat dot on `status_ok`, the Settings selection glides and the section slides in, switches and
  segmented controls spring, the lock's shackle closes, a wrong passphrase shakes the locked card,
  pages come in (`viewIn`). With the system's Reduce motion or Raven's Reduced motion nothing moves.
- **Honest states:** "held by a friend" only when a waiting message's path says so; the route line's
  path is the last delivery's, and a waiting friend's line is dashed with "Waiting for {name}"; the
  path icon in the sidebar shows only while the friend is in touch; group members' copies show their
  state (waiting, sent, delivered, failed, passed on by another member) but no path, which the
  engine doesn't report per member.

## Groups

Built on `groups.*` (API.md "Groups", from feature/groups; 16 members, the creator is the only admin
and can't leave, joining is automatic). `groups.list` `available: false` (a release engine, or no
`RAVEN_LAB_GROUPS`) hides the Groups section and New group. Events: `group_message` (a member's
message; the event's `message` is decoded as a GroupMessage) and `group_changed` (the group is read
again: `groups.get`, `groups.history`). MockRaven has one demo group, "Book club" (you are its admin;
Ali, Mina, and Sam who is not your friend), with per-member receipts, and plays a receipt and a
message in its demo stream. Screens: the group chat, New group, Members (add and remove for the
admin, Leave for the others) and Leave. Snapshots `46`-`49`.

## Engine extras the app uses

raven-client sends a few fields beyond the first contract (API.md lists them). The app uses:

- `events.poll` `reset`: events were lost, so the app reloads identity, settings, node status,
  contacts and histories (`AppModel.reloadAfterReset`), plays no motion for what it missed, and polls
  on from the engine's `seq`.
- `NodeStatus.state`: "Starting…" only while the engine says `starting` (a node that runs without
  a listener no longer looks like it is starting).
- `node.stop` `stop` / `note`: when the node is left running (`managed`, `advice`, `still_running`)
  the note is shown; a `failed` stop shows the error with the reason under Details.
- `profile.state` `detail`: under Details on the "can't read" screen.
- `messages.retry` of an ended message returns a new message (new id, `replaces`): the app swaps the
  bubble for it, as it already did with the returned message.

Other extras (`blocked`, `lab`, `address_missing`, `already_saved`, the check details `reason`,
`position`, `case_only`, `mismatches`, `may_arrive_twice`, `may_have_arrived`, `note` on
`identity.create`) are ignored for now.

## Check words, old code and privacy

- **Old code.** Under the typed words, "Older Raven? Use the old code instead" switches Check words to
  the old code: the intro talks about the code (`check.oldCode.intro`), your old code to read aloud in
  groups of four as in the design (`If4x 36FU omFi`, also on the security-words screen), one plain field
  for theirs (no chips, no completion, no marks; spaces and separators are ignored, letter case matters),
  and only match or mismatch at the end (`verify.check_old_code`). A match verifies the friend
  as the words do; "Use the 10 words instead" switches back. Snapshots `26`-`28`.
- **Three mismatches** (words and old code together) withdraw Check and show "Stop here…" (snapshot
  `29`). Typing hints: "Type the words with English letters." and "Type at least 3 letters of word
  {n}." depend only on what was typed.
- **Privacy.** Settings > Privacy reads `privacy.state`. While `available` is false, "Encrypt
  everything" and "Erase Raven from this computer…" are disabled with "Preview, not in this release"
  (as in the Windows app), and "Lock now" (menu bar and command) is disabled. When available, the
  switch follows `encrypted` and calls `privacy.encrypt`; Erase opens a sheet that enables **Erase**
  only after "erase" is typed, then calls `privacy.erase` and returns to the welcome screen
  (snapshot `30`).

## Honest motion

Every animation starts from an engine event (`AppModel.apply`): `status_ok` pulses the heart (500 ms),
`send_started` sends a ▸ out along the route line (800 ms), `receipt` brings a ✓ back (650 ms) and
sets "Delivered", `incoming` sends a ◂ in and slides the bubble in (350 ms, bold for 1.5 s),
`presence` blinks the dot, `retry` sends one ring around the dot (1 s), `node` (starting) shows the
spinner in the network chip. Delivery is never shown before a `receipt`. In-touch dots breathe with a
Core Animation loop (no app CPU); the menu-bar mark breathes in four steps of the 1-second clock
while Raven listens; the welcome mark fades and scales in once.

The system's Reduce motion or Raven's own Reduced motion setting stops all of it; texts still update.
An idle window runs two timers: the 1-second clock (relative times, the menu-bar mark) and the
`events.poll` loop.

## Notes

- **`@ViewState` instead of `@State`.** In the macOS 27 SDK `@State` is a macro whose plugin ships
  only with Xcode, so a package built with the Command Line Tools cannot use it. `@ViewState` wraps a
  `State` value in a `DynamicProperty` and behaves the same (also under Xcode). `#Preview` is not
  used for the same reason; `RavenSnapshots` replaces previews.
- **swift-testing with the Command Line Tools.** They ship `Testing.framework` but not XCTest, and
  the default build system misses two paths. `Package.swift` adds the macro plugin folder and an rpath
  for the test target, only when the active developer directory is the Command Line Tools.
- **Snapshots.** `ImageRenderer` cannot draw AppKit-backed views (text fields, pop-up menus, scroll
  views, split views, AppKit switches). Raven's switches, buttons and chips are drawn in SwiftUI
  anyway (they follow the tokens); text fields, menus and scroll views get a drawn look-alike when
  the `ravenSnapshot` environment flag is set, and the split view is drawn as two columns.
- **Chat header.** The name, Verified badge, path pill and heartbeat sit in a header row inside the
  chat (as in the mockup), not in the window's NSToolbar, so they also appear in snapshots.
- **Polling.** As API.md says: `events.poll` every 500 ms while the main window is open, every 5 s
  when only the menu bar extra is alive (`AppModel.pollInterval`); opening the window polls at once.
  A poll never overlaps another one. Motions that arrive in the same poll play in order.
- **Threading.** `raven_call` may block, so no engine call runs on the main thread: every engine runs
  its blocking `raven_call`-shaped function on `EngineQueue` (a concurrent dispatch queue) and resumes
  the `@MainActor` `AppModel` with the result. `MockRaven` does the same (creating the identity
  blocks for 0.9 s there) and counts calls that arrive on the main thread; a test expects none.

## License

Copyright (C) 2026 ASHCO. GNU Affero General Public License v3.0 (`LICENSE`; notice and pending
additional terms in `NOTICE`). The Raven name, logo and app icon are covered
separately by `core/TRADEMARK.md` and `core/ASSET_LICENSE.md`. Security issues: please write to
security@raven-messager.com (`SECURITY.md`), not a public issue.
