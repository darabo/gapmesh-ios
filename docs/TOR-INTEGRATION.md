Tor-by-default integration (scaffold)

Overview
- All network traffic is routed via a local Tor SOCKS5 proxy by default, with fail-closed behavior when Tor isn’t ready. There are no user-visible settings.
- This repo now includes a minimal TorManager and TorURLSession to make dropping in an embedded Tor framework straightforward.

Key pieces
- TorManager
  - Boots Tor, manages a DataDirectory under Application Support, exposes SOCKS at 127.0.0.1:39050, and provides awaitReady().
  - Fails closed by default until Tor is bootstrapped. For local development only, define BITCHAT_DEV_ALLOW_CLEARNET to bypass Tor.
- TorURLSession
  - Provides a shared URLSession configured with a SOCKS5 proxy when Tor is enforced/ready.
  - NostrRelayManager and GeoRelayDirectory now use this session and await Tor readiness before starting network activity.

Drop‑in steps
1) Build or obtain a small Tor framework
   - Recommended: Tor C (client-only) with static linking and dead-strip.
   - Configure Tor with a minimal feature set:
     ./configure \
       --enable-static \
       --disable-asciidoc --disable-unittests --disable-manpage \
       --disable-zstd --disable-lzma --enable-zlib \
       --disable-systemd --disable-ptrace --disable-seccomp
     CFLAGS="-Os -fdata-sections -ffunction-sections" \
     LDFLAGS="-Wl,-dead_strip"
   - Build a tiny OpenSSL/LibreSSL (no engines, strip symbols) or reuse system crypto where permitted on macOS.

2) Add the framework to Xcode targets
   - Drop your xcframework into `Frameworks/`. The project is prewired in `project.yml` to link/embed `Frameworks/tor-nolzma.xcframework` (rename yours to match, or update the path).
   - Ensure the binary includes the slices you need (iOS device/simulator and/or macOS). If your xcframework lacks simulator slices, you can still build/run on device or macOS arm64; simulator will fail to link.
   - On iOS, it will be embedded and signed automatically.

3) Wire Tor bootstrap in TorManager.startTor()
   - Two paths are already implemented:
     - If a module named `Tor` is present (iCepa API), it starts `TORThread` directly.
     - Otherwise, it attempts a dynamic load (`dlopen`) of a bundled framework binary named `tor-nolzma.framework/tor-nolzma` (or `Tor.framework/Tor`), resolves `tor_run_main`, and launches Tor on a background thread.
   - `TorManager` writes a torrc and then probes `127.0.0.1:39050` until ready.

4) Verify networking
   - On app launch, TorManager.startIfNeeded() is called implicitly by awaitReady().
   - NostrRelayManager.connect() awaits readiness, then creates WebSocket tasks via TorURLSession.shared.
   - GeoRelayDirectory.fetchRemote() awaits readiness, then fetches via TorURLSession.shared.

5) Optional macOS optimization
   - Detect a system Tor binary (e.g., /opt/homebrew/bin/tor) and run it as a subprocess to avoid bundling. Keep the embedded fallback for portability.

torrc template
The generated torrc (under Application Support/bitchat/tor/torrc) is:

  DataDirectory <AppSupport>/bitchat/tor
  ClientOnly 1
  SOCKSPort 127.0.0.1:39050
  ControlPort 127.0.0.1:39051
  CookieAuthentication 1
  AvoidDiskWrites 1
  MaxClientCircuitsPending 8

Dev bypass (local only)
- To temporarily allow direct network without Tor for local development:
  - Add Swift compiler flag: BITCHAT_DEV_ALLOW_CLEARNET
  - This enables a clearnet session in TorURLSession when Tor isn’t present.
  - Never enable this in release builds.

Notes
- We intentionally do not change any app-level APIs: consumers simply use TorURLSession via existing code paths.
- When Tor is missing in release builds, the app will not connect (fail-closed), logging a clear reason.

---

## MasterDnsVPN (instead of Slipstream): Feasibility + Implementation Walkthrough

### Goal
- Replace the planned Slipstream DNS-tunnel path with [MasterDnsVPN](https://github.com/masterking32/MasterDnsVPN) as the censorship-bypass transport that Tor can chain through.
- During implementation, pin to a specific MasterDnsVPN release tag or commit SHA to keep builds reproducible.

### Feasibility (short answer)
- **Server side:** High feasibility. MasterDnsVPN has Linux server setup and clear DNS delegation requirements.
- **macOS app:** Medium feasibility. You can run the MasterDnsVPN client binary as a local SOCKS5 proxy and point Tor to it.
- **iOS app (in-process):** Low feasibility for a quick migration. MasterDnsVPN is written in Go as a CLI app; iOS cannot spawn arbitrary long-lived subprocesses. You need an embeddable library bridge (C ABI) or a Network Extension architecture.

### Recommended integration path
1) Start with a desktop proof-of-concept
   - Run MasterDnsVPN client externally (SOCKS5 listener, e.g. `127.0.0.1:18000`).
   - Add `Socks5Proxy 127.0.0.1:18000` to Tor config and confirm Tor bootstrap/relay traffic works through it.
   - Validate Nostr relay connect and `GeoRelayDirectory` fetch still work over `TorURLSession`.

2) Define the app-facing contract first
   - Keep the same runtime contract as `SlipstreamManager`: start, stop, isRunning, lastLogLine, error state, local SOCKS endpoint.
   - Add a provider abstraction so Tor can consume `upstreamProxyAddress` without caring whether backend is Slipstream or MasterDnsVPN.

3) Replace UI wiring before transport internals
   - Update Settings copy and keys from “Slipstream” to “MasterDnsVPN” (domain, resolver list, encryption key).
   - Keep the feature disabled by default until health checks and crash recovery are complete.

4) Wire Tor to upstream SOCKS proxy
   - Extend `TorManager.torrcTemplate()` to conditionally add:
     - `Socks5Proxy 127.0.0.1:18000` (replace with your configured listener)
   - Use the same host:port configured in the MasterDnsVPN client listener (`LISTEN_IP`/`LISTEN_PORT`).
   - Regenerate torrc on toggles/restarts and restart Tor cleanly when proxy mode changes.

5) Implement a MasterDnsVPN runtime adapter
   - **Short-term (macOS):** launch bundled binary with config file and parse logs.
   - **iOS-ready path:**
     - Expose a C-callable bridge from Go (`-buildmode=c-archive` + exported C symbols).
     - Wrap the generated artifacts in an xcframework.
     - Call the bridge from Swift (same style as current C bridge usage).
   - Ensure adapter provides non-blocking startup and a deterministic shutdown API.

6) Add operational safeguards
   - Health probes on local SOCKS port.
   - Automatic fail-closed behavior when proxy is enabled but unavailable.
   - Crash notification + Tor restart backoff.
   - Config validation for tunnel domain(s), resolver(s), and key before start.

7) Rollout plan
   - Phase A: macOS-only feature flag.
   - Phase B: internal iOS test builds with bridge-based runtime.
   - Phase C: remove Slipstream code paths/package once parity is confirmed.

### Repository touch points for migration
- `bitchat/Services/SlipstreamManager.swift`:
  - Direct replacement migration: rename this to `MasterDnsVPNManager`.
  - Multi-backend migration: introduce a generic `DNSTunnelManager` abstraction instead.
- `bitchat/Views/Tabs/SettingsTabView.swift` → toggle and advanced fields.
- `bitchat/Localizable.xcstrings` → rename user-facing strings.
- `localPackages/Tor/Sources/TorManager.swift` → conditional `Socks5Proxy` torrc line.

### Risks to plan for
- iOS embedding complexity for Go runtime and binary size impact.
- App Store review sensitivity around bundled censorship-bypass networking.
- DNS path variance across resolvers/ISPs; requires conservative defaults and telemetry.
