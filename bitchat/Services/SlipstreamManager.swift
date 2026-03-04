import Foundation
#if canImport(Network)
import Network
#endif
#if canImport(Darwin)
import Darwin
#endif

// ============================================================================
// SlipstreamManager.swift — Censorship Bypass via DNS Tunneling (iOS)
// ============================================================================
//
// WHAT THIS FILE DOES:
// In countries that censor the internet, Tor connections may be blocked.
// Slipstream gets around this by disguising Tor traffic as DNS queries
// (which are almost never blocked, since they're needed for basic internet).
//
// HOW IT WORKS (Data Flow):
//   App → Tor (SOCKS5 @ port 39050)
//       → Local TCP Proxy (port 7000)
//           → Slipstream Client (in-process)
//               → DNS queries to DNS server
//                   → Slipstream Server
//                       → Tor relay (guard node)
//
// WHY IN-PROCESS?
// iOS doesn't allow spawning separate processes (no posix_spawn).
// So the Slipstream C library is compiled directly into the app binary
// and runs on a background thread.
//
// WHEN IS IT USED?
// Only when the user enables it via settings. It adds latency (DNS overhead)
// but makes Tor connections nearly impossible to block.
//
// C BRIDGE:
// The functions below (slipstream_host_start/stop/etc.) are defined in C
// and linked via the CSlipstreamHost target. Swift calls them using
// @_silgen_name (a way to call C functions by name without a header file).
//

// ── C bridge to the embedded Slipstream library (CSlipstreamHost.c) ─────────
// These functions are provided by the SlipstreamC target in the Slipstream
// local package. They run the Slipstream QUIC-over-DNS client in-process on a
// background pthread — no subprocess involved.

@_silgen_name("slipstream_host_start")
private func slipstream_host_start(_ domain: UnsafePointer<CChar>,
                                   _ resolver: UnsafePointer<CChar>,
                                   _ listenPort: Int32) -> Int32

@_silgen_name("slipstream_host_stop")
private func slipstream_host_stop() -> Int32

@_silgen_name("slipstream_host_is_running")
private func slipstream_host_is_running() -> Int32

@_silgen_name("slipstream_host_last_log")
private func slipstream_host_last_log() -> UnsafePointer<CChar>

@_silgen_name("slipstream_host_last_error")
private func slipstream_host_last_error() -> UnsafePointer<CChar>?

/// Manages the Slipstream (QUIC-over-DNS) censorship-bypass client on iOS.
///
/// Slipstream creates a local TCP proxy that tunnels traffic through DNS queries,
/// enabling connectivity in censored networks. When active, Tor routes its guard
/// connections through this proxy via the `Socks5Proxy` torrc directive.
///
/// Architecture: App → Tor(SOCKS5@39050) → Socks5Proxy@7000 → Slipstream → DNS → Server → microsocks
///
/// The Slipstream client runs in-process as a linked static library (like C-Tor),
/// NOT as a separate subprocess. iOS does not allow posix_spawn of executables.
/// Build the library using `tools/build_slipstream_ios.sh`.
@MainActor
public final class SlipstreamManager: ObservableObject {

    public static let shared = SlipstreamManager()

    // MARK: - Configuration

    /// Local TCP proxy port for Slipstream (Tor connects here as Socks5Proxy)
    let socksPort: Int = 7000
    let socksHost: String = "127.0.0.1"

    // MARK: - State

    public enum SlipstreamState: String {
        case off = "Off"
        case starting = "Starting"
        case running = "Running"
        case error = "Error"
        case stopping = "Stopping"
    }

    @Published public private(set) var state: SlipstreamState = .off
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastLogLine: String = ""
    @Published public private(set) var errorMessage: String?

    // MARK: - Settings (persisted in SecureStorageManager)

    private let enabledKey = "slipstreamEnabled"
    private let domainKey = "slipstreamDomain"
    private let resolverKey = "slipstreamResolver"

    public var isEnabled: Bool {
        get { false }
        set { SecureStorageManager.shared.set(false, forKey: enabledKey) }
    }

    public var domain: String {
        get { SecureStorageManager.shared.object(forKey: domainKey) as? String ?? "t.gapmesh.com" }
        set { SecureStorageManager.shared.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: domainKey) }
    }

    public var resolver: String {
        get { SecureStorageManager.shared.object(forKey: resolverKey) as? String ?? "1.1.1.1" }
        set { SecureStorageManager.shared.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: resolverKey) }
    }

    /// Returns true if Slipstream is enabled and has a valid domain configured.
    public var isConfiguredAndEnabled: Bool {
        isEnabled && !domain.isEmpty
    }

    private var healthCheckTask: Task<Void, Never>?
    private var logPollingTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    /// Start the Slipstream client in-process on a background thread.
    /// Returns immediately; use `waitUntilReady()` to block until the proxy is listening.
    public func start(tunnelDomain: String? = nil, dnsResolver: String? = nil) {
        guard state != .starting && state != .running && state != .stopping else { return }

        let dom = tunnelDomain ?? domain
        let res = dnsResolver ?? resolver

        guard !dom.isEmpty else {
            state = .error
            errorMessage = "Tunnel domain is required"
            return
        }

        state = .starting
        lastLogLine = "Starting Slipstream client..."
        errorMessage = nil

        // Start in-process via C bridge (non-blocking — launches a pthread)
        let rc = slipstream_host_start(dom, res, Int32(socksPort))

        if rc != 0 {
            state = .error
            switch rc {
            case -1: errorMessage = "Slipstream is already running"
            case -2: errorMessage = "Invalid domain or resolver"
            case -3: errorMessage = "Failed to resolve DNS resolver address"
            case -4: errorMessage = "Failed to create background thread"
            default: errorMessage = "Start failed (code \(rc))"
            }
            lastLogLine = errorMessage ?? "Unknown error"
            return
        }

        // Start polling for log updates and port readiness
        startLogPolling()
        startReadinessCheck()
    }

    /// Wait asynchronously until the Slipstream proxy port is reachable.
    /// Returns true if ready within the timeout, false otherwise.
    public func waitUntilReady(timeout: TimeInterval = 15.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if state == .running { return true }
            if state == .error { return false }
            if await probePort(port: socksPort) {
                state = .running
                isRunning = true
                lastLogLine = "Slipstream connected"
                startHealthCheck()
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        }
        // Timeout — check if the process is still alive
        if slipstream_host_is_running() == 0 {
            state = .error
            errorMessage = "Slipstream process exited unexpectedly"
            if let errPtr = slipstream_host_last_error() {
                errorMessage = String(cString: errPtr)
            }
        } else {
            state = .error
            errorMessage = "Proxy not reachable after \(Int(timeout))s"
        }
        return false
    }

    /// Stop the Slipstream client.
    public func stop() {
        guard state != .off && state != .stopping else { return }
        state = .stopping
        isRunning = false

        healthCheckTask?.cancel()
        healthCheckTask = nil
        logPollingTask?.cancel()
        logPollingTask = nil

        // Signal shutdown and wait for the background thread to exit.
        // This must complete fully before start() can be called again.
        Task.detached(priority: .userInitiated) {
            let _ = slipstream_host_stop()
            // Wait for the OS to release the socket (TIME_WAIT)
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            await MainActor.run { [weak self] in
                self?.state = .off
                self?.isRunning = false
                self?.lastLogLine = ""
            }
        }
    }

    /// Restart with current settings.
    public func restart() {
        stop()
        // Wait long enough for stop() to complete and port to be freed.
        // stop() sets state to .off after ~2s; start() guards against .stopping.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.start()
        }
    }

    /// Returns the SOCKS5 proxy address when running (for torrc Socks5Proxy).
    public func proxyAddress() -> String? {
        guard isRunning else { return nil }
        return "\(socksHost):\(socksPort)"
    }

    // MARK: - Readiness Check

    /// After starting, probe the local TCP port to detect when Slipstream is ready.
    private func startReadinessCheck() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let ready = await self.waitUntilReady(timeout: 15.0)
            if ready {
                await MainActor.run {
                    self.startHealthCheck()
                }
            }
        }
    }

    // MARK: - Log Polling

    /// Poll the C bridge for log updates and surface them to the UI.
    private func startLogPolling() {
        logPollingTask?.cancel()
        logPollingTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let logPtr = slipstream_host_last_log()
                let logStr = String(cString: logPtr)
                if !logStr.isEmpty {
                    await MainActor.run { [weak self] in
                        if self?.lastLogLine != logStr {
                            self?.lastLogLine = logStr
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            }
        }
    }

    // MARK: - Health Check

    /// Periodic health check: ensure the background thread is still alive.
    /// Checks every 3s so a crash is detected quickly (before relay retries exhaust).
    /// On crash, posts `.SlipstreamDidCrash` so Tor/Nostr layers can recover.
    private func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
                let alive = slipstream_host_is_running() != 0
                if !alive {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.state = .error
                        self.isRunning = false
                        self.lastLogLine = "Slipstream process died"
                        if let errPtr = slipstream_host_last_error() {
                            self.errorMessage = String(cString: errPtr)
                        }
                        // Notify the system so Tor and relay layers can recover
                        NotificationCenter.default.post(name: .SlipstreamDidCrash, object: nil)
                    }
                    break
                }
            }
        }
    }

    // MARK: - Port Probing

    private func probePort(port: Int) async -> Bool {
        #if canImport(Network)
        return await withCheckedContinuation { cont in
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                cont.resume(returning: false)
                return
            }
            let conn = NWConnection(
                to: .hostPort(host: .ipv4(.loopback), port: nwPort),
                using: .tcp
            )
            var resumed = false
            let resumeOnce: (Bool) -> Void = { value in
                if !resumed { resumed = true; cont.resume(returning: value) }
            }
            conn.stateUpdateHandler = { connState in
                switch connState {
                case .ready: resumeOnce(true); conn.cancel()
                case .failed, .cancelled: resumeOnce(false); conn.cancel()
                default: break
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
                resumeOnce(false); conn.cancel()
            }
            conn.start(queue: DispatchQueue.global(qos: .utility))
        }
        #else
        return false
        #endif
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let SlipstreamDidCrash = Notification.Name("SlipstreamDidCrash")
}
