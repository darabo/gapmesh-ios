// CSlipstreamHost.h — C bridge for embedded Slipstream client
//
// Runs the Slipstream QUIC-over-DNS client in-process on a background thread,
// similar to how CTorHost.c embeds the Tor client. The Slipstream library is
// linked as a static library (.xcframework) and called directly — no subprocess.
//
// The client listens on a local TCP port and tunnels traffic through DNS queries
// to a Slipstream server, which forwards to a SOCKS5 proxy (microsocks).
// Tor then routes its outbound connections through this local TCP port.

#ifndef CSLIPSTREAM_HOST_H
#define CSLIPSTREAM_HOST_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Start the Slipstream client on a background thread.
///
/// @param domain       Tunnel domain (e.g., "t.gapmesh.com"). Required.
/// @param resolver     Upstream DNS resolver (e.g., "1.1.1.1"). Required.
/// @param listen_port  Local TCP listen port (e.g., 7000).
/// @return 0 on success, negative on error:
///         -1  already running
///         -2  invalid arguments
///         -3  resolver address parse failure
///         -4  pthread_create failure
int slipstream_host_start(const char *domain, const char *resolver, int listen_port);

/// Request a clean shutdown of the Slipstream client.
/// Sets the internal shutdown flag and waits for the background thread to exit
/// (with a timeout). Non-blocking if not running.
///
/// @return 0 on success, -1 if not running, positive = client exit code
int slipstream_host_stop(void);

/// Returns nonzero if the Slipstream background thread is running.
int slipstream_host_is_running(void);

/// Returns the last log line from the Slipstream client (may be empty).
/// The returned pointer is valid until the next call to any slipstream_host_ function.
const char *slipstream_host_last_log(void);

/// Returns the last error message, or NULL if no error.
const char *slipstream_host_last_error(void);

#ifdef __cplusplus
}
#endif

#endif // CSLIPSTREAM_HOST_H
