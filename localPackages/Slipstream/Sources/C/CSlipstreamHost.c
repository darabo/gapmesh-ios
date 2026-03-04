// CSlipstreamHost.c — In-process Slipstream client via background pthread
//
// Embeds the Slipstream QUIC-over-DNS client as a library, running its blocking
// event loop on a dedicated background thread. The client creates a local TCP
// listener that tunnels traffic through DNS queries to a Slipstream server.
//
// Shutdown is achieved by setting the client's `should_shutdown` global flag,
// which causes the QUIC packet loop to close all connections and return.
//
// This follows the same pattern as CTorHost.c for Tor embedding.

#include "CSlipstreamHost.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

// ── Forward declarations from Slipstream's public API (slipstream.h) ────────

typedef struct st_address_t {
    struct sockaddr_storage server_address;
    _Bool added;
} address_t;

int picoquic_slipstream_client(int listen_port, struct st_address_t* server_addresses,
                               size_t server_address_count, const char* domain_name,
                               const char* cc_algo_id, _Bool gso, size_t keep_alive_interval);

// From picoquic (picosocks.h) — resolve a server name to sockaddr
int picoquic_get_server_address(const char* server_name, int server_port,
                                struct sockaddr_storage* addr, int* is_name);

// ── Slipstream's global shutdown flag (defined in slipstream_client.c) ──────
// We set this to 1 to trigger a clean shutdown of the QUIC packet loop.
extern volatile sig_atomic_t should_shutdown;

// ── Static state ────────────────────────────────────────────────────────────

static pthread_t slipstream_thread;
static int thread_started = 0;
static int client_exit_code = 0;

// Persisted copies of arguments for the background thread
static char domain_copy[256] = {0};
static char resolver_copy[256] = {0};
static int  listen_port_copy = 7000;

// Last log / error strings (simple static buffers)
static char last_log[512] = {0};
static char last_error[512] = {0};

// ── Background thread entry ─────────────────────────────────────────────────

static void *slipstream_thread_main(void *arg) {
    (void)arg;

    // Reset the shutdown flag before starting
    should_shutdown = 0;
    client_exit_code = 0;
    last_error[0] = '\0';

    snprintf(last_log, sizeof(last_log), "Slipstream starting (domain=%s resolver=%s port=%d)",
             domain_copy, resolver_copy, listen_port_copy);

    // Parse resolver address
    struct st_address_t resolver_addr;
    memset(&resolver_addr, 0, sizeof(resolver_addr));

    char server_name[256];
    int server_port = 53;

    // Handle [IPv6]:port format
    if (resolver_copy[0] == '[') {
        const char *closing = strchr(resolver_copy, ']');
        if (closing) {
            size_t len = (size_t)(closing - (resolver_copy + 1));
            if (len < sizeof(server_name)) {
                memcpy(server_name, resolver_copy + 1, len);
                server_name[len] = '\0';
                if (closing[1] == ':') {
                    server_port = atoi(closing + 2);
                }
            }
        }
    } else {
        // host or host:port
        char *colon = strchr(resolver_copy, ':');
        if (colon && strchr(colon + 1, ':') == NULL) {
            // Single colon → IPv4:port
            size_t len = (size_t)(colon - resolver_copy);
            if (len < sizeof(server_name)) {
                memcpy(server_name, resolver_copy, len);
                server_name[len] = '\0';
                server_port = atoi(colon + 1);
            }
        } else {
            strncpy(server_name, resolver_copy, sizeof(server_name) - 1);
            server_name[sizeof(server_name) - 1] = '\0';
        }
    }

    int is_name = 0;
    if (picoquic_get_server_address(server_name, server_port,
                                    &resolver_addr.server_address, &is_name) != 0) {
        snprintf(last_error, sizeof(last_error), "Cannot resolve resolver: %s", resolver_copy);
        snprintf(last_log, sizeof(last_log), "Error: %s", last_error);
        client_exit_code = -3;
        return (void *)(intptr_t)client_exit_code;
    }

    snprintf(last_log, sizeof(last_log), "Slipstream connecting (resolver=%s:%d)...",
             server_name, server_port);

    // Auto-reconnect loop: if the client exits (server closed connection,
    // transient bind failure) wait for port release and retry — unless
    // shutdown was explicitly requested.
    int rc = 0;
    int max_retries = 5;
    for (int attempt = 0; attempt <= max_retries && !should_shutdown; attempt++) {
        if (attempt > 0) {
            snprintf(last_log, sizeof(last_log), "Reconnecting (attempt %d/%d)...",
                     attempt, max_retries);
            // Backoff: 2s, 3s, 4s, 5s, 6s — checked in 500ms steps so
            // we can bail quickly if stop() sets should_shutdown.
            int wait_intervals = 4 + (attempt * 2);
            for (int i = 0; i < wait_intervals && !should_shutdown; i++) {
                usleep(500000);
            }
            if (should_shutdown) break;
            snprintf(last_log, sizeof(last_log), "Slipstream connecting (resolver=%s:%d)...",
                     server_name, server_port);
        }

        rc = picoquic_slipstream_client(
            listen_port_copy,
            &resolver_addr,
            1,                  // one resolver
            domain_copy,
            "dcubic",           // congestion control
            false,              // GSO disabled (not useful on mobile)
            400                 // keep-alive interval ms
        );

        client_exit_code = rc;
        if (should_shutdown) break;  // Clean shutdown requested

        snprintf(last_log, sizeof(last_log), "Slipstream exited (code %d), will retry...", rc);
    }

    if (!should_shutdown && rc != 0) {
        snprintf(last_error, sizeof(last_error),
                 "Slipstream failed after %d attempts (last code %d)", max_retries + 1, rc);
    }
    snprintf(last_log, sizeof(last_log), "Slipstream stopped (exit code %d)", rc);

    // Mark thread as finished so is_running() returns 0 on natural exit
    thread_started = 0;

    return (void *)(intptr_t)rc;
}

// ── Public API ──────────────────────────────────────────────────────────────

int slipstream_host_start(const char *domain, const char *resolver, int listen_port) {
    if (thread_started) return -1;
    if (!domain || !domain[0] || !resolver || !resolver[0]) return -2;
    if (strlen(domain) >= sizeof(domain_copy) || strlen(resolver) >= sizeof(resolver_copy)) return -2;

    // Wait for the port to be free (handles TIME_WAIT from previous instance)
    for (int attempt = 0; attempt < 10; attempt++) {
        int probe_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (probe_fd < 0) break;

        int reuse = 1;
        setsockopt(probe_fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons((uint16_t)listen_port);
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

        int bind_rc = bind(probe_fd, (struct sockaddr *)&addr, sizeof(addr));
        close(probe_fd);

        if (bind_rc == 0) break;  // Port is free
        snprintf(last_log, sizeof(last_log), "Waiting for port %d to be released...", listen_port);
        usleep(500000);  // 500ms
    }

    // Store arguments
    strncpy(domain_copy, domain, sizeof(domain_copy) - 1);
    domain_copy[sizeof(domain_copy) - 1] = '\0';
    strncpy(resolver_copy, resolver, sizeof(resolver_copy) - 1);
    resolver_copy[sizeof(resolver_copy) - 1] = '\0';
    listen_port_copy = listen_port;

    last_error[0] = '\0';
    snprintf(last_log, sizeof(last_log), "Starting Slipstream client...");

    int rc = pthread_create(&slipstream_thread, NULL, slipstream_thread_main, NULL);
    if (rc != 0) {
        snprintf(last_error, sizeof(last_error), "pthread_create failed: %d", rc);
        return -4;
    }

    thread_started = 1;
    return 0;
}

int slipstream_host_stop(void) {
    if (!thread_started) return -1;

    snprintf(last_log, sizeof(last_log), "Stopping Slipstream...");

    // Signal the Slipstream event loop to shut down
    should_shutdown = 1;

    // Block until the thread exits. The shutdown flag causes the QUIC event
    // loop to close all connections and return within a few seconds.
    void *retval = NULL;
    pthread_join(slipstream_thread, &retval);
    thread_started = 0;  // Ensure cleared (thread may have cleared it already)

    snprintf(last_log, sizeof(last_log), "Slipstream stopped");

    return (int)(intptr_t)retval;
}

int slipstream_host_is_running(void) {
    return thread_started;
}

const char *slipstream_host_last_log(void) {
    return last_log;
}

const char *slipstream_host_last_error(void) {
    if (last_error[0] == '\0') return NULL;
    return last_error;
}
