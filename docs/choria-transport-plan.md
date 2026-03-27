# Choria Transport: Project Plan

This document describes the project plan and roadmap for the Choria transport
in OpenBolt. It covers the phased implementation approach, current progress,
and future work.

For user-facing documentation, see [choria-transport.md](choria-transport.md).
For developer documentation, see [choria-transport-dev.md](choria-transport-dev.md).
For test environment setup, see [choria-transport-testing.md](choria-transport-testing.md).

---

## Overview

The Choria transport lets OpenBolt communicate with nodes via Choria's NATS
pub/sub messaging infrastructure instead of SSH/WinRM. It uses the
`choria-mcorpc-support` gem as the client library, sending RPC requests to
agents running on target nodes.

The transport is implemented in phases, each adding capabilities based on
which Choria agents are available on the remote nodes:

| Phase | Agents Required | Capabilities Added |
|-------|----------------|-------------------|
| Phase 1 | bolt_tasks (ships with Choria+Puppet) | `run_task` (OpenVox/Puppet Server tasks only) |
| Phase 2 | shell >= 1.2.0 (separate install) | `run_command`, `run_script`, `run_task` (local tasks) |
| Phase 3 | bolt_tasks | [foreman_openbolt](https://github.com/overlookinfra/foreman_openbolt) and [smart_proxy_openbolt](https://github.com/overlookinfra/smart_proxy_openbolt) Choria transport support (bolt_tasks only) |
| Phase 4 | file-transfer (new, to be written) | `upload`, `download` (any size, chunked) |
| Phase 5 | (all above) | Full plan support including apply blocks |

---

## Architecture

### How Choria RPC Works

```
OpenBolt Controller                    NATS Broker                Target Node
     |                                     |                         |
     |-- RPC Request (JSON) -->            |                         |
     |   (via MCollective::RPC::Client)    |-- message -->           |
     |                                     |                    [Choria Server]
     |                                     |                    [Agent receives]
     |                                     |                    [Agent executes]
     |                                     |<-- reply --             |
     |<-- RPC Response (JSON) --           |                         |
```

Key points:
- **No persistent connections.** Each RPC call is a request/reply over NATS
  pub/sub.
- **Multi-target by default.** One RPC call addresses all targets in a batch.
  NATS pub/sub delivers it in parallel.
- **DDLs are mandatory.** The MCollective RPC client loads an agent's DDL at
  construction time. DDLs for `rpcutil` and `bolt_tasks` ship with the gem.
  The shell DDL is bundled with OpenBolt.

### Transport Design

The transport extends `Transport::Base` directly (not `Simple`), because
Choria's pub/sub model doesn't fit the persistent connection/shell abstraction
that `Simple` assumes. Each operation:

1. Configures the MCollective client (one-time setup)
2. Discovers agents on target nodes (cached after first contact)
3. Partitions targets by agent availability, emitting errors for incapable ones
4. Performs the operation on capable targets
5. Returns per-target results

### Agent Discovery

On first contact with a target, two RPC calls discover what's available:

1. `rpcutil.agent_inventory` returns the list of installed agents with versions
2. `rpcutil.get_fact(os.family)` returns the OS family for platform dispatch

Results are cached per target for the transport instance's lifetime.

### Thread Safety

OpenBolt runs batches in parallel threads sharing the same transport instance:

- Client configuration is protected by a mutex (one-time setup)
- All RPC calls are serialized to prevent concurrent MCollective usage
- Agent cache uses a thread-safe concurrent map

For detailed threading analysis, see
[choria-transport-dev.md](choria-transport-dev.md#threading-model).

---

## Phase 1: bolt_tasks Agent Support

**Status: Complete**

Phase 1 delivers task execution via the bolt_tasks agent, which downloads
task files from an OpenVox/Puppet Server and executes them on target nodes.

What shipped:
- `run_task` via bolt_tasks agent with async execution and polling
- `run_command`, `run_script` return clear per-target errors when the shell
  agent is not available (rather than crashing)
- `upload`, `download` return "not yet supported" errors
- Connectivity checking via `rpcutil.ping`
- Agent detection with per-target caching
- Client configuration with NATS, TLS, and collective overrides
- Config class with validation for all transport options
- Transport and config registration in OpenBolt's executor and config systems

---

## Phase 2: Shell Agent Support

**Status: Complete**

Phase 2 adds command and script execution via the shell agent, plus an
alternative task execution path that uploads task files directly instead of
downloading from an OpenVox/Puppet Server.

What shipped:
- `run_command` with async execution, timeout, and process kill on timeout
- `run_script` with remote tmpdir creation, script upload via base64, and
  cleanup
- `run_task` via shell agent with support for all input methods (environment,
  stdin, both)
- Deterministic agent selection via `choria-agent` config and `--choria-agent`
  CLI flag (no automatic fallback between agents)
- Batched shell polling via `shell.list` + `shell.statuses` for scalability
- Platform-aware command builders for POSIX and Windows (PowerShell)
- Interpreter support via the `interpreters` config option

### Shell Agent Actions Used

| Action | Usage | Response |
|--------|-------|----------|
| `run` | Synchronous execution (infrastructure ops) | `stdout`, `stderr`, `exitcode` |
| `start` | Start async command | `handle` (process identifier) |
| `list` | List all managed processes on a node | Array of `{ id, ... }` |
| `statuses` | Batch status of multiple handles | Per-handle `stdout`, `stderr`, `exitcode`, `status` |
| `kill` | Kill background process | (acknowledgement) |

---

## Phase 3: Foreman OpenBolt Support

**Status: Not started**

### Goal

Update [foreman_openbolt](https://github.com/overlookinfra/foreman_openbolt) and
[smart_proxy_openbolt](https://github.com/overlookinfra/smart_proxy_openbolt)
to support the Choria transport. This integration will only support the
bolt_tasks agent path (task execution via OpenVox/Puppet Server file downloads), not
the shell agent. Eventually, when plan support is introduced to these components,
and Phase 5 of this project is complete, the Foreman integration will have full
OpenBolt support.

### Scope

- Foreman OpenBolt will be able to run tasks on Choria-managed nodes via
  bolt_tasks
- No `run_command`, `run_script`, or shell agent support
- Configuration will be limited to the bolt_tasks-compatible options

---

## Phase 4: File Transfer Agent

**Status: Not started**

### Goal

Implement `upload` and `download` support via a new `file-transfer` Choria
agent that efficiently sends and receives large files, chunked to stay under
the NATS message size limit.

### Background: NATS and Choria Constraints

NATS itself is binary-safe -- payloads are opaque byte arrays and the server
never inspects them. However, the Choria RPC protocol serializes all messages
as nested JSON. The DDL type system supports string, integer, float, number,
boolean, array, and hash -- no binary type. This means binary file data cannot
be sent as-is through Choria RPC action inputs; it must be encoded (typically
base64) to survive JSON serialization.

NATS has a configurable max message size (default 1MB, max 64MB). The Choria
broker inherits this as `plugin.choria.network.client_max_payload`.

NATS JetStream (called "Choria Streams" in Choria) is available but not
enabled by default -- it requires `plugin.choria.network.stream.store` to be
set. When enabled, Choria uses JetStream for event streams, KV store, and
leader elections. JetStream also provides an Object Store feature for chunked
binary storage, though Choria does not use it today.

### Approach Options

The final approach will be chosen when this phase begins. Three options are
documented here with their tradeoffs.

#### Option A: Compressed + Base64 via Choria RPC

The simplest approach. File data is optionally gzip-compressed, then base64-encoded, and
sent as string action inputs through standard Choria RPC calls. The agent
decompresses and writes to disk.

This works entirely within the existing Choria RPC framework using a Ruby
agent, which aligns with the OpenBolt community's expertise.

**Pros:**
- Works with any Choria deployment (no JetStream, no special config)
- Ruby agent, consistent with existing agent ecosystem
- Simple protocol, uses standard RPC request/reply

**Cons:**
- Base64 encoding adds ~33% size overhead (on the compressed data)
- Each chunk is a full RPC round-trip with JSON serialization overhead
  (four nested JSON layers plus base64 at the transport level)
- Chunk size limited by NATS max message size minus RPC overhead

**Chunk size calculation:**
```
max_chunk_bytes = (message_size_limit - overhead_estimate) * 3 / 4
```

With the default 1MB message limit:
- RPC overhead (headers, JSON keys, etc.): ~4,096 bytes
- Available for base64 payload: 1,044,480 bytes
- Raw data per chunk (before compression): 1,044,480 * 3 / 4 = 783,360
  bytes (~765 KB)
- Conservative default: 512 KB chunks (leaves generous headroom)

Compression reduces actual wire size significantly for compressible files
(text, configs, scripts, catalogs). For already-compressed files (zip, tar.gz,
images, binaries), compression is skipped to avoid wasting CPU.

#### Option B: Hybrid RPC + Direct NATS Binary Channel

Uses Choria RPC for coordination (setup, teardown, status) and a separate
direct NATS connection for the binary data transfer. This avoids JSON
serialization and base64 encoding on the data path entirely.

The file-transfer agent would need to be written in Go, since Go agents have
clean access to the raw NATS connection via `Instance.Connector().Nats()`.
The Ruby side (OpenBolt client) would open a second `NATS::IO::Client`
instance for the data channel, since the existing `NatsWrapper` feeds all
subscriptions into a single shared receive queue that would conflict with
RPC traffic.

**Pros:**
- Zero encoding overhead on the data path (raw compressed bytes over NATS)
- Efficient use of the full NATS message size for data
- Binary-safe without any serialization workarounds

**Cons:**
- Requires a Go agent (different language from the rest of the ecosystem)
- More complex protocol (RPC for control plane, raw NATS for data plane)
- OpenBolt needs a second NATS connection with its own TLS configuration
- Must coordinate subject naming and cleanup between the two channels

#### Option C: JetStream Object Store

Both sides use the NATS JetStream Object Store for chunked binary transfer.
Object Store handles chunking (default 128KB, configurable), integrity
verification (SHA-256), and reassembly natively. RPC calls coordinate the
transfer (initiate, confirm completion, clean up).

Like Option B, the agent would need to be Go since Ruby's NATS client does
not expose JetStream Object Store APIs.

**Pros:**
- Native chunking with built-in SHA-256 integrity checking
- No file size limit (constrained only by disk space)
- Handles all chunk management, retries, and verification internally
- Well-supported by NATS -- this is the recommended approach for large
  payloads in NATS documentation

**Cons:**
- Requires JetStream enabled on the Choria broker (not the default)
- Requires a Go agent
- Adds a deployment prerequisite that other phases do not have
- Object Store is not used anywhere else in Choria today

### Common Design (All Approaches)

Regardless of approach, the file-transfer agent needs these filesystem
operations:

| Action | Description | Inputs | Outputs |
|--------|-------------|--------|---------|
| `mkdir` | Create directory | `path`, `mode` | `created` |
| `stat` | Get file/dir metadata | `path` | `exists`, `size`, `type`, `mode`, `mtime` |
| `delete` | Remove file/directory | `path`, `recursive` | `deleted` |

The chunk transfer actions will vary by approach but the transfer protocol
follows the same pattern:

**Upload (OpenBolt to remote node):**
1. `stat` the destination to check if it exists (optional, for overwrite
   semantics)
2. `mkdir` parent directories if needed
3. Read local file, compress (if beneficial), and send in chunks
4. Agent writes chunks to a temp file, renames on completion
5. Return result with bytes transferred

**Download (remote node to OpenBolt):**
1. `stat` the remote file to get size
2. Request chunks until the full file is received
3. Decompress (if compressed) and write each chunk to local file
4. Return result with bytes transferred

**Directory transfers:**
- For upload: walk the local directory tree, transfer each file
- For download: use `stat` to detect directory, then walk remote tree

### Config Changes

New options:
- `chunk-size` (Integer, default: 524288 = 512KB) - Size of file transfer
  chunks in bytes

### Testing Strategy

1. Unit tests mocking the file-transfer agent responses
2. Chunk boundary conditions (exactly 1 chunk, multiple chunks, empty file)
3. Compression behavior (compressible files, already-compressed files, empty
   files)
4. Directory traversal (nested dirs, empty dirs, symlinks)
5. Resume/retry on chunk failure
6. Integration tests against a real Choria cluster with the agent

---

## Phase 5: Full Plan Support

**Status: Not started**

### Goal

All OpenBolt plan features work with the Choria transport, including:
- Plan execution with multiple steps
- Apply blocks (Puppet code application)
- Plan functions (run_command, run_script, run_task, upload_file, download_file)
- Error handling (catch_errors, run_plan)
- Parallel execution within plans
- Variables, iterators, conditionals

### What Already Works

With Phases 1+2+4, the following plan functions should work automatically
because they delegate to the transport's public methods:
- `run_command()` via transport.run_command
- `run_script()` via transport.run_script
- `run_task()` via transport.run_task
- `upload_file()` via transport.upload
- `download_file()` via transport.download

### What Needs Work: Apply Blocks

Apply blocks compile a Puppet catalog on the controller and apply it on the
target. This requires:

1. **Puppet library on the target.** The `puppet_library` plugin hook
   installs Puppet on the target if needed.
2. **Catalog application.** The compiled catalog is sent to the target and
   applied via `libexec/apply_catalog.rb`.

The apply mechanism works by:
1. Compiling the catalog locally (controller-side, OpenBolt handles this)
2. Uploading the catalog, plugins, and the apply helper script to the target
3. Running the apply helper script on the target

With Phases 2+4, steps 2 and 3 should work:
- Phase 4's `upload` sends the catalog and plugin files
- Phase 2's `run_command`/`run_script` executes the apply helper

### Investigation Needed

- **Apply prep:** How does `Bolt::ApplyPrep` work? Does it use specific
  transport methods, or does it go through the standard
  run_task/upload/run_command path?
- **Plugin sync:** How are Puppet plugins synced to the target? Is this a
  separate transport call or part of the apply mechanism?
- **Hiera data:** How is Hiera data sent to the target for apply?
- **puppet_library hook:** How does this interact with the Choria transport? 
  The default bootstrap hook installs Puppet via a task, which should work
  with Phase 2. But we are also probably assuming all nodes have OpenVox/Puppet installed already.

### Testing Strategy

1. Simple apply block (single resource)
2. Apply with Hiera data
3. Apply with custom modules
4. Plan with mixed steps (run_command + run_task + apply)
5. Error handling in plans (catch_errors around Choria operations)
6. Parallel execution within plans
