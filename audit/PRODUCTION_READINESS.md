# mcp_dart — Production Readiness Audit

Comprehensive audit of `mcp_dart` across stdio, HTTP/SSE, and streamable HTTPS transports.
Focus: durability, recoverability, error handling, platform parity (macOS/Linux/Windows).
Updated: 2026-03-25

---

## Open issues

### High

#### H4. Client class — `sessionId != null` early return skips init

**File:** `client/client.dart` (~167–169)

When `transport.sessionId != null`, `connect()` returns without running `initialize`. `_serverCapabilities` stays null. Any code using `assertCapabilityForMethod` with `enforceStrictCapabilities` will throw.

**Fix:** At minimum, populate capabilities from cache or document the constraint.

---

### Medium

#### M1. No inbound backpressure on ReadBuffer

`iostream.dart` (70–75) — `stream.listen` never pauses. Combined with bounded `ReadBuffer`, a fast producer will hit the 10 MB cap and tear down the transport rather than applying flow control.

#### M3. Server stdio — no signal handling

`server/stdio.dart` — no SIGINT/SIGTERM handlers; graceful shutdown requires external wiring.

#### M5. Shelf adapter — missing SSE disconnect cleanup

`server/streamable_https.dart` (~730–735) — adapter GET/POST SSE paths have no `done` listener (shelf doesn't expose one). `_adapterStreamMapping` entries leak until `close()`. Documented in code as an inherent shelf limitation.

#### M6. `StreamableMcpServer` — UTF-8 decode before try/catch

`server/streamable_mcp_server.dart` (~237) — `utf8.decode(bodyBytes)` is outside the `jsonDecode` try/catch, so invalid UTF-8 becomes a 500 instead of a JSON-RPC parse error.

#### M7. Shelf GET path missing event replay vs dart:io

`server/streamable_https.dart` (~614–617) — adapter GET does not implement `Last-Event-ID` replay; documented but creates feature parity gap.

#### M8. Sensitive/large lines logged on JSON parse failure

`shared/stdio.dart` — `deserializeMessage` logs the full line on parse failure. Can flood logs or leak data.

---

### Low / by design

- **No automatic reconnection in stdio** — by design; server state is lost on process death.
- **Windows `kill()`** — Dart's `ProcessSignal` API handles platform differences.
- **Single-threaded concurrent `send()`** — Dart isolate model prevents data races; ordering follows call order.
- **`onerror` callback exceptions swallowed** — intentional; prevents user bugs from crashing protocol.
- **`token.usage` / `commands.available` explicit no-ops** — documented rationale in OS transform.
- **`fs/read` / `fs/write` reserved** — wired with error responses; harness never sends.

---

## Test coverage gaps

| Area | Missing |
|------|---------|
| **Stdio client** | Large buffer / no-newline DoS (cap is tested; backpressure is not) |
| **Stdio server** | Signal handling; concurrent close race |
| **Protocol** | Error handler ordering edge cases |
| **Streamable HTTPS client** | Concurrent send ordering; timeout interaction with reconnect |
| **Streamable HTTPS server** | Shelf adapter disconnect cleanup; adapter vs dart:io feature parity |
| **Cross-platform** | Windows process lifecycle; Windows named pipe (if applicable); SIGTERM behavior differences |

---

## Resolved

| ID | Title | Resolution |
|----|-------|------------|
| C1 | ReadBuffer unbounded growth — OOM / DoS | `ReadBuffer` now has `maxBufferSize` (10 MB default); `append()` returns false on overflow; transports report error and close. |
| C2 | UTF-8 decode `null` conflated with "need more data" | `readMessage()` throws `MalformedLineException`; `_processReadBuffer` catches it and continues to next line. |
| C3 | Streamable HTTPS client — reconnect timers not cancelled on `close()` | `_reconnectTimer` field added, cancelled in `close()`. `_startOrAuthSse` gates on `_isClosed`. `_sseActive` guard prevents duplicate streams. |
| C4 | Streamable HTTPS client — reconnect only if SSE `id:` seen | `handleReconnection` no longer guards on `eventId != null`; reconnects without `Last-Event-ID` when no events were received. |
| C5 | Streamable HTTPS client — `maxRetries: 0` means infinite retries | Guard changed to `maxRetries >= 0 && _reconnectAttemptCount >= maxRetries`. Cumulative counter persists across cycles. |
| C6 | SSE server — swallowed `start()` errors | Generic errors rethrown after partial cleanup. `UnimplementedError` also rethrown with `propagateToCallback: false`. |
| C7 | SSE server — socket `onError` doesn't trigger `close()` | `onError` handler now calls `close()` after `onerror`. |
| C8 | Protocol `_onclose` — `catchError` may pass non-`Error` to `_onerror(Error)` | Debounced notification path wraps: `e is Error ? e : StateError('$e')`. Dead resolver loop in `_onclose` removed. |
| C9 | Streamable HTTPS server — unbounded body read | `_collectBytes` and `_collectBytesFromStream` enforce configurable `maxBodySize`; return 413 on exceeded. |
| C10 | Streamable HTTPS server — concurrent GET race | Conflict check returns HTTP 409 if `_streamMapping[_standaloneSseStreamId]` already exists. Stream assigned before flushing headers. |
| H1 | Server stdio — stdin `onError` doesn't call `close()` | `_onErrorCallback` now calls `close()` after `onerror`. |
| H2 | Server stdio — `send()` returns success without flush | Now calls `await _stdout.flush()`. |
| H3 | Client class — stale state after disconnect | `McpClient.close()` clears `_serverCapabilities`, `_serverVersion`, `_instructions`, and cached tool metadata. |
| H5 | CORS: `*` + `Allow-Credentials: true` | `Access-Control-Allow-Credentials` header removed. Comment documents the Fetch spec constraint. |
| H6 | Content-type validation uses `contains()` — false positives | Exact MIME type comparison via `split(';').first.trim().toLowerCase()`. |
| H7 | McpServer `remove()` doesn't actually remove registrations | All `remove()` methods (resources, templates, tools, prompts) now directly remove from their backing maps. |
| H8 | McpServer `registerCapabilities` after `connect` throws | `McpServer` constructor eagerly calls `_ensureResourceHandlersInitialized()`, `_ensureToolHandlersInitialized()`, `_ensurePromptHandlersInitialized()`, `_ensureTaskHandlersInitialized()`. |
| H9 | Streamable HTTPS server — `_requestToStreamMapping` leak on disconnect | `response.done.then` and `.catchError` both call `_requestToStreamMapping.removeWhere(...)`. |
| H10 | No HTTP request timeouts on client | Configurable `httpTimeout` (default 30s) wraps all `_httpClient.send()` calls via `_sendWithTimeout()`. |
| H11 | SSE client — abort listeners accumulate per reconnect | Per-stream `abortSubscription` created and cancelled in `onDone`/`onError`. |
| H12 | Task notification errors silently swallowed | Notification errors now logged at warning level via `_logger.warn`. Awaited instead of fire-and-forget. |
| H13 | `response.done.then(...)` without `catchError` | All `response.done.then(...)` chains now include `.catchError(...)` with cleanup and error reporting. |
| M2 | Streamable HTTPS server — `send()` SSE not awaited | Request-scoped SSE streams now use the same `_writeSSEEvent` path with proper completion tracking. |
| M4 | `close()` in iostream `send()` error path not awaited | `await close()` in `send()` error handler (iostream.dart line 214). |

---

## Change log

| Round | Date | Summary |
|-------|------|---------|
| 1 | 2026-03-25 | Initial audit generated from parallel read-only codebase scans. 10 Critical, 13 High, 8 Medium items identified. |
| 2 | 2026-03-25 | Fixed all 10 Critical items (C1–C10): ReadBuffer bounds, MalformedLineException sentinel, reconnect timer lifecycle, reconnect-without-id, maxRetries semantics, SSE start() error propagation, socket error → close(), _onclose type safety, body size limits, concurrent GET guard. |
| 3 | 2026-03-25 | Fixed 12 of 13 High items (H1–H3, H5–H13): server stdio close-on-error + flush, client stale state cleanup, CORS fix, MIME parsing, remove() no-op, eager capability registration, request-to-stream leak, HTTP timeouts, abort listener cleanup, task notification logging, response.done error handling. H4 remains open (sessionId early return). |
| 4 | 2026-03-25 | Fixed 2 Medium items (M2, M4): iostream send() error path await, SSE write tracking. Added tests for ReadBuffer overflow, MalformedLineException, reconnect timer cancellation, maxRetries semantics, server stdio close/flush, SSE server lifecycle, client state cleanup, content-type validation, body size limits, concurrent GET, response.done errors. |
