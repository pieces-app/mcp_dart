# mcp_dart — Production Readiness Audit

Comprehensive audit of `mcp_dart` across stdio, HTTP/SSE, and streamable HTTPS transports.
Focus: durability, recoverability, error handling, platform parity (macOS/Linux/Windows).
Generated: 2026-03-25 from parallel read-only codebase audits.

---

## Critical (must fix)

### C1. ReadBuffer unbounded growth — OOM / DoS

**Files:** `shared/stdio.dart` (12–18, 36–39), used by `shared/iostream.dart`, `client/stdio.dart`, `server/stdio.dart`

`BytesBuilder` grows without limit if the peer never sends `\n`. A malicious or buggy peer can exhaust memory.

**Fix:** Add a `maxBufferSize` (e.g. 10 MB) to `ReadBuffer`. On exceeded: clear buffer, invoke `onerror`, close transport.

---

### C2. UTF-8 decode `null` conflated with "need more data"

**Files:** `shared/stdio.dart` (44–50), `shared/iostream.dart` (118–119), `client/stdio.dart` (214–216)

`readMessage()` returns `null` both when there's no complete line AND when a line failed UTF-8 decode. The `_processReadBuffer` while-loop treats any `null` as "stop" — leaving valid subsequent lines **unprocessed** until the next chunk. If no further chunks arrive, those lines are **permanently stuck**.

**Fix:** Return a sentinel (e.g. a `ReadResult` enum) distinguishing "need more data" from "line skipped". Continue looping on skip; break only on need-more-data.

---

### C3. Streamable HTTPS client — reconnect timers not cancelled on `close()`

**File:** `client/streamable_https.dart` (267–291, 466–471)

`_scheduleReconnection` uses `Future.delayed` with no cancellation. `close()` sets `_isClosed` but doesn't cancel pending delayed futures. `_startOrAuthSse` doesn't check `_isClosed` at entry. Result: **new SSE connections after shutdown**.

**Fix:** Track scheduled reconnect timers; cancel them in `close()`. Gate `_startOrAuthSse` on `!_isClosed`.

---

### C4. Streamable HTTPS client — reconnect only if SSE `id:` seen

**File:** `client/streamable_https.dart` (345–360, 417–429)

`handleReconnection` only calls `_scheduleReconnection` when `lastEventId != null`. If the connection drops before any SSE event with `id:`, **no reconnect** happens even when `shouldReconnect` is true.

**Fix:** Allow reconnect without `Last-Event-ID`; omit the header if no ID is available.

---

### C5. Streamable HTTPS client — `maxRetries: 0` means infinite retries

**File:** `client/streamable_https.dart` (270–273, 281–286)

Guard is `if (maxRetries > 0 && attemptCount >= maxRetries)` — when `maxRetries == 0`, the condition is never true, so failures loop forever.

**Fix:** Treat `maxRetries == 0` as "no retries" or use `maxRetries != null && maxRetries > 0`.

---

### C6. SSE server — swallowed `start()` errors → "connected" but broken

**File:** `server/sse.dart` (104–106)

Generic errors in `start()` (e.g. `detachSocket` failure) are caught and only logged — **not rethrown**. `Protocol.connect()` treats `start()` as successful, so the transport looks "connected" while `_sink` is null and no SSE stream is established.

**Fix:** Rethrow after logging so `connect()` fails properly.

---

### C7. SSE server — socket `onError` doesn't trigger `close()`

**File:** `server/sse.dart` (95–98)

On socket error, `onerror` is called but `close()` is not — transport stays "open" with a dead socket. Matches the same pattern we fixed in stdio client.

**Fix:** Call `close()` after `onerror`.

---

### C8. Protocol `_onclose` — `catchError` may pass non-`Error` to `_onerror(Error)`

**File:** `shared/protocol.dart` (~1011)

`.catchError((e) => _onerror(e))` — `catchError` passes `Object`, but `_onerror` expects `Error`. A non-`Error` async failure could throw a type error at runtime.

**Fix:** Wrap: `_onerror(e is Error ? e : StateError('$e'))`.

---

### C9. Streamable HTTPS server — unbounded body read

**Files:** `server/streamable_https.dart` (936–947, 1198–1210), `server/streamable_mcp_server.dart`

`_collectBytes` / `_collectBytesFromStream` buffer the **entire** POST body with no max size. Memory exhaustion / DoS risk.

**Fix:** Add configurable `maxBodySize` (e.g. 4 MB). Return 413 on exceeded.

---

### C10. Streamable HTTPS server — concurrent GET race

**File:** `server/streamable_https.dart` (384–412)

Two concurrent standalone GETs can both pass the conflict check and both proceed. The second overwrites `_streamMapping[_standaloneSseStreamId]`. Adapter path has no conflict check at all (~670–671).

**Fix:** Atomic check-and-set (e.g. set the map entry before flushing headers, or use a lock).

---

## High (should fix)

### H1. Server stdio — stdin `onError` doesn't call `close()`

**File:** `server/stdio.dart` (84–90)

Same pattern as C7: error reported via `onerror` but transport stays "started" — zombie state.

**Fix:** Call `close()` from `_onErrorCallback`.

---

### H2. Server stdio — `send()` returns success without flush

**File:** `server/stdio.dart` (152–164)

`send()` does `_stdout.write(jsonString)` then returns `Future.value()` — no `flush()`, no `done` awaiting. Caller thinks message is sent when it's only buffered. On process exit, data can be lost.

**Fix:** `await _stdout.flush()` or document that delivery is best-effort.

---

### H3. Client class — stale state after disconnect

**File:** `client/client.dart`

`_serverCapabilities`, `_serverVersion`, `_instructions`, tool caches are **not** cleared in `_onclose`. After disconnect, `getServerCapabilities()` returns stale data while transport is null.

**Fix:** Clear client-specific fields in an `_onclose` override or expose a `reset()`.

---

### H4. Client class — `sessionId != null` early return skips init

**File:** `client/client.dart` (~170–173)

When `transport.sessionId != null`, `connect()` returns without running `initialize`. `_serverCapabilities` stays null. Any code using `assertCapabilityForMethod` with `enforceStrictCapabilities` will throw.

**Fix:** At minimum, populate capabilities from cache or document the constraint.

---

### H5. CORS: `*` + `Allow-Credentials: true`

**File:** `server/streamable_mcp_server.dart` (~453–462)

Browsers reject this combination per Fetch spec. Credentialed cross-origin requests will fail.

**Fix:** Either use specific origin (from `Origin` header) when credentials are needed, or remove `Access-Control-Allow-Credentials`.

---

### H6. Content-type validation uses `contains()` — false positives

**File:** `server/streamable_https.dart` (~704–706, ~973–974)

`contentType.contains("application/json")` matches `application/json-seq` and other subtypes.

**Fix:** Use exact match or proper MIME parsing.

---

### H7. McpServer `remove()` doesn't actually remove registrations

**File:** `server/mcp_server.dart` (~231–256)

`remove()` delegates to `update(uri: null)` / `update(name: null)`, but `update` only removes when the new value is **non-null**. So `remove()` is a no-op.

**Fix:** Handle `null` in `update()` as a deletion signal, or implement `remove()` directly.

---

### H8. McpServer `registerCapabilities` after `connect` throws

**File:** `server/server.dart` (~95–106), `server/mcp_server.dart` (~809–818)

`registerCapabilities` is forbidden after connect. But `McpServer._ensureToolHandlersInitialized` etc. call it lazily on first tool/resource use. If `connect()` runs before any registration, the first registration throws.

**Fix:** Either initialize all capability categories in the constructor, or allow late registration with a server-side `capabilities/changed` notification.

---

### H9. Streamable HTTPS server — `_requestToStreamMapping` leak on disconnect

**File:** `server/streamable_https.dart` (1139–1157)

On SSE disconnect, `_streamMapping[streamId]` is removed but `_requestToStreamMapping` entries for that stream's request IDs are not — leak until `close()`.

**Fix:** Remove `_requestToStreamMapping` entries when the stream is cleaned up.

---

### H10. No HTTP request timeouts on client

**File:** `client/streamable_https.dart` (~218, ~521, ~637)

No timeout on `_httpClient.send(request)`. Dead TCP connections hang forever.

**Fix:** Add configurable `httpTimeout` on all `send` calls.

---

### H11. SSE client — abort listeners accumulate per reconnect

**File:** `client/streamable_https.dart` (433–436)

Each `_handleSseStream` adds a listener on `_abortController.stream` to cancel the SSE subscription. Old listeners are never removed — grows with each reconnect.

**Fix:** Cancel the previous abort listener before adding a new one, or use a single-use mechanism.

---

### H12. Task notification errors silently swallowed

**File:** `server/tasks/session.dart` (41–43)

`.catchError((e) { /* Ignore errors broadcasting */ })` — task status notification failures are dropped with no log.

**Fix:** At minimum, log at warning level.

---

### H13. `response.done.then(...)` without `catchError` — unhandled async error

**File:** `server/streamable_https.dart` (419–422, 465–468, 1154–1157)

`HttpResponse.done` can complete with an error; these `.then` handlers have no `.catchError`. Unhandled async errors can crash the isolate depending on zone configuration.

**Fix:** Add `.catchError` to all `response.done.then(...)` chains.

---

## Medium (improve)

### M1. No inbound backpressure on ReadBuffer

`iostream.dart` (70–75) — `stream.listen` never pauses. Combined with unbounded `ReadBuffer`, a fast producer grows memory without bound.

### M2. Streamable HTTPS server — `send()` SSE not awaited for request-scoped streams

`server/streamable_https.dart` (~1371) — `_writeSSEEvent` is not awaited; ordering and backpressure are weaker than standalone path.

### M3. Server stdio — no signal handling

`server/stdio.dart` — no SIGINT/SIGTERM handlers; graceful shutdown requires external wiring.

### M4. `close()` in iostream `send()` error path not awaited

`shared/iostream.dart` (~186) — `close()` is called without `await`; race with follow-up logic.

### M5. Shelf adapter — missing SSE disconnect cleanup

`server/streamable_https.dart` (633–675, 835–846) — adapter GET/POST SSE paths have no `done` listener; `_adapterStreamMapping` leaks until `close()`.

### M6. `StreamableMcpServer` — UTF-8 decode before try/catch

`server/streamable_mcp_server.dart` (~200–218) — `utf8.decode(bodyBytes)` is outside the `jsonDecode` try/catch, so invalid UTF-8 becomes a 500 instead of a JSON-RPC parse error.

### M7. Shelf GET path missing event replay vs dart:io

`server/streamable_https.dart` (~614–617) — adapter GET does not implement `Last-Event-ID` replay; documented but creates feature parity gap.

### M8. Sensitive/large lines logged on JSON parse failure

`shared/stdio.dart` (81, 84) — full line content in log; can flood logs or leak data.

---

## Low / by design

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
| **Stdio client** | Stdout EOF while process lives; pending requests + kill; restart after close; large buffer / no-newline DoS |
| **Stdio server** | Stdin error → zombie; broken stdout; concurrent close; signal handling |
| **Protocol** | `_requestResolvers` failing on close; error handler ordering; non-`Error` in `catchError` |
| **Streamable HTTPS client** | Reconnect timer cancellation on close; `maxRetries: 0`; reconnect without `id:`; concurrent send; HTTP timeout |
| **Streamable HTTPS server** | Concurrent GET race; body size limit; `_requestToStreamMapping` leak; adapter vs dart:io parity |
| **SSE server** | `start()` failure → connected state; socket error → zombie; POST before SSE ready |
| **McpServer** | `remove()` no-op; post-connect registration; stale client state after disconnect |
| **Cross-platform** | Windows process lifecycle; Windows named pipe (if applicable); SIGTERM behavior differences |
