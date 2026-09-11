# Choria Transport: Project Plan

This document describes the project plan and roadmap for the Choria transport
in OpenBolt. It covers the phased implementation approach, current progress,
and future work.

For user-facing documentation, see the
[Choria transport user guide](https://docs.openvoxproject.org/openbolt/latest/choria-transport.html).
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
| Phase 2 | shell >= 1.2.1 (separate install) | `run_command`, `run_script`, `run_task` (local tasks) |
| Phase 3 | bolt_tasks (shell optional for local tasks) | [foreman_openbolt](https://github.com/overlookinfra/foreman_openbolt) and [smart_proxy_openbolt](https://github.com/overlookinfra/smart_proxy_openbolt) run tasks over the Choria transport |
| Phase 4 | file_transfer (new, to be written) | `upload`, `download` (any size, chunked) |
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
- Deterministic agent selection via `task-agent` config and `--choria-task-agent`
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

**Status: Complete**

Phase 3 delivers the Choria transport in
[foreman_openbolt](https://github.com/overlookinfra/foreman_openbolt) and
[smart_proxy_openbolt](https://github.com/overlookinfra/smart_proxy_openbolt).

What shipped:
- Choria as a selectable transport for running tasks
- Task agent selection (bolt_tasks or shell)
- Choria options with a `choria-` prefix, passed to OpenBolt as CLI flags
- Zero-config client defaults in the proxy (bundled client config, SSL
  settings and certname derived from the proxy certificate)

Plan support in the Foreman integration follows Phase 5. See
[Follow-up Work](#follow-up-work).

---

## Phase 4: File Transfer Agent

**Status: In progress**

### Goal

Implement `upload` and `download` via a new `file_transfer` Choria agent that
sends and receives files of any size, chunked to stay under the NATS message
size limit. There is no upper bound on file size. Both sides stream one chunk
at a time, so memory use is bounded by the chunk size, not the file size. The
task paths also use this agent to deliver task arguments that exceed their
agents' input limits as a file on the target, which apply blocks in Phase 5
require.

Transferring files this way is nowhere near as efficient as a download from a
file server. Every chunk is a signed, base64-encoded RPC round trip. The agent
is intended for moving smaller files around a fleet. Gigabytes belong on a
file server, not on Choria, and the user guide says so.

### Requirements

- Any file size, with memory bounded by the chunk size on both sides
- Fleet scale: a few MB to 10,000 nodes, or from 10,000 nodes, across several
  collectives and through federated brokers
- Windows targets
- Apply in Phase 5 runs without the shell agent, so the bolt_tasks path uses
  this agent for large task arguments

### Constraints

- The Choria broker's NATS payload limit is 1 MiB and has no Choria
  configuration key. Every transfer is chunked, and the request envelope
  (identity filter, federation headers) shares that budget with the data.
- The client base64-encodes the action input, then base64-encodes the whole
  signed request again at the transport layer with line breaks that JSON
  escapes, so raw chunk bytes expand by over 80 percent on the wire.
- The Choria server starts a new process for every request to a Ruby or
  external agent. A Ruby agent run through the MCollective shim loads
  MCollective on each request (about half a second). An external agent
  written in Ruby loads only the JSON library (about 25 ms).
- A request that exceeds the agent's DDL timeout gets no reply at all, so
  transfers are short per-chunk actions, never one long action.
- Fleet nodes on a broker in JWT mode may only use the RPC request and reply
  subjects. They get no custom subjects, no Object Store, and no Key-Value
  access, which rules out any direct NATS or JetStream data path.
- The Ruby client publishes one copy of every request per target, since the
  direct addressing the transport uses never takes the library's broadcast
  path, and the whole per-target publish loop runs inside a publish timeout
  that defaults to 2 seconds. It queues replies without bound and drops
  replies once a subscription buffer of 64MB overflows.
- The shell agent DDL caps the `command` input at 10,240 characters, so the
  current base64 upload path carries at most about 7.5KB of raw content per
  call.
- The bolt_tasks agent caps task input at 100KB and only runs task files it
  fetches from an OpenVox/Puppet Server. Apply passes the catalog and a
  plugin tarball as task arguments, which run to hundreds of KB.

### Decisions

- Approach: Option A, chunked transfer over standard Choria RPC
- The agent is a Choria external agent written in Ruby. It ships as an
  executable plus DDL in the same Puppet module layout as the shell agent,
  and it needs Ruby on the node, which every bolt_tasks node has.
- Agent name `file_transfer`, repository `file_transfer-agent`, Puppet module
  and class `mcollective_agent_file_transfer`, following the `<agent>-agent`
  and `mcollective_agent_<agent>` convention of the other Choria plugin agents
- Options B and C are rejected. Fleet nodes cannot reach the subjects they
  need, and the Ruby NATS client OpenBolt uses has no JetStream support.
- Temporary storage on a node is addressed by a session UUID and a relative
  name, never by a path the controller computes. The agent owns the temp
  root through its own setting, and there is no general delete action.
- Authorization stays with Choria. The agent has no allowlist of its own.
  Action policies gate callers and actions, and the rego provider gates
  paths, since it sees the action arguments.

### Investigation Needed

- External agent execution on a Windows Choria server
- An upstream Choria broker setting for the NATS payload limit. NATS allows
  up to 8MB, which would cut the chunk count up to eightfold, and the
  transport's runtime sizing would use it without changes.

### Background: NATS and Choria Constraints

NATS itself is binary-safe -- payloads are opaque byte arrays and the server
never inspects them. However, the Choria RPC protocol serializes all messages
as nested JSON. The DDL type system supports string, integer, float, number,
boolean, array, and hash -- no binary type. This means binary file data cannot
be sent as-is through Choria RPC action inputs; it must be encoded (typically
base64) to survive JSON serialization.

NATS has a configurable max message size (default 1MB, up to 64MB, with
values over 8MB discouraged). The Choria broker exposes no setting for it, so
Choria broker deployments run at 1MB. Only a deployment on a standalone NATS
server can raise it. The server advertises the limit to every client in the
`INFO` message at connect time.

NATS JetStream (called "Choria Streams" in Choria) is available but not
enabled by default -- it requires `plugin.choria.network.stream.store` to be
set. When enabled, Choria uses JetStream for event streams, KV store, and
leader elections. JetStream also provides an Object Store feature for chunked
binary storage, though Choria does not use it today.

### Approach Options

Option A was chosen. Options B and C are kept for reference.

#### Option A: Compressed + Base64 via Choria RPC

The simplest approach. File data is optionally gzip-compressed, then base64-encoded, and
sent as string action inputs through standard Choria RPC calls. The agent
decompresses and writes to disk.

This works entirely within the existing Choria RPC framework and keeps the
agent in Ruby.

**Pros:**
- Works with any Choria deployment (no JetStream, no special config)
- Ruby agent, consistent with existing agent ecosystem
- Simple protocol, uses standard RPC request/reply

**Cons:**
- Base64 is applied twice, on the action input and again on the whole signed
  request at the transport layer, so raw bytes expand by over 80 percent
- Each chunk is a full RPC round-trip with JSON serialization overhead
  (four nested JSON layers plus base64 at the transport level)
- Chunk size limited by NATS max message size minus the request envelope

**Chunk size:**

The chunk's base64 text sits inside the signed request, which is then
base64-encoded again, so roughly:
```
request_json_budget = (max_payload - transport_wrapper) * 3 / 4
chunk_base64_budget = request_json_budget - envelope - margin
raw_chunk_bytes     = chunk_base64_budget * 3 / 4
```

With the 1MB limit and a small batch that is roughly 555KB of raw data per
chunk. The envelope carries the identity filter, so it grows with the batch,
and at 10,000 targets the raw chunk falls to roughly 270KB. The default
`chunk-size` is 512KB, under the small-batch ceiling with headroom. Larger
batches get a smaller computed chunk.

The transport computes the chunk for each batch at run time, never from
stored measurements, so a new Choria or client library version needs no
retest:
- It reads `max_payload` from the NATS `INFO` the client received at connect
- It computes the envelope for the batch by serializing the request without
  a chunk through the installed client, a local calculation with no network
  involved, so the filter, credentials, signature, protocol version, and
  encoding are counted as the installed version produces them
- The chunk is the smaller of `chunk-size` and that budget minus a reserve
  for what the controller cannot observe: headers federation brokers add in
  flight, and the reply envelope the node's server builds around a download
  chunk
- A size guard at the wrapper's publish method compares every outgoing
  message, as serialized, against the limit before it is sent. An oversized
  request never leaves the controller. The guard raises immediately with the
  exact overshoot, and the transport shrinks the chunk by that amount plus a
  small cushion and resends.
- Downloads cannot get that signal, because an oversized reply fails on the
  node and never reaches the controller. The request tells the agent the
  maximum reply size, derived from the same budget minus the reserve, and
  chunk requests use a short timeout derived from observed chunk latency. A
  whole group going silent on the same chunk size is treated as a sizing
  failure. The transport reduces the chunk by 20 percent for that group and
  retries, down to a floor, before reporting the targets as failed.
- Every reduction is a prominent warning to the user, not a silent retry. It
  names the cause (a guard rejection with the overshoot in bytes, or a group
  that went silent), the limit the broker advertised, the chunk size before
  and after, the affected targets, and the remedy: lower `chunk-size` to
  avoid the retries, or raise the broker's payload limit. It is emitted once
  per cause per run with a count, not once per chunk, and the transfer still
  completes.
- If a future client version removes the publish hook, the transport falls
  back to a conservative fraction of the limit and logs a warning naming the
  cause

Compression reduces actual wire size significantly for compressible files
(text, configs, scripts, catalogs). For already-compressed files (zip, tar.gz,
images, binaries), compression is skipped to avoid wasting CPU.

#### Option B: Hybrid RPC + Direct NATS Binary Channel

Uses Choria RPC for coordination (setup, teardown, status) and a separate
direct NATS connection for the binary data transfer. This avoids JSON
serialization and base64 encoding on the data path entirely.

The agent would need to be written in Go, since Go agents have
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

### Design

The agent's DDL, semantics, and specs live in the
[file_transfer-agent](https://github.com/overlookinfra/file_transfer-agent)
repository. This section records what the transport depends on.

**Actions.** Every string input carries a validation regex and a byte
limit. The client checks them before sending and the Choria server checks
them before running the agent.

| Action | Purpose | Inputs | Outputs |
|--------|---------|--------|---------|
| `mktemp` | Create a session directory, sweep stale sessions | `session` | `path`, `swept` |
| `put` | Write one chunk into a session, verify and move on the last | `session`, `name`, `offset`, `data`, `compressed`, `final`, `sha256`, `destination`, `mode` | `bytes`, `size`, `sha256` |
| `cleanup` | Remove a session directory | `session` | `removed` |
| `get` | Read one chunk | `path`, `offset`, `max_bytes`, `compress` | `data`, `bytes`, `compressed`, `eof`, `size` |
| `stat` | Describe a path | `path`, `checksum` | `exists`, `type`, `symlink`, `size`, `mode`, `mtime`, `sha256` |
| `list` | List one page of a directory | `path`, `offset`, `limit` | `entries`, `total` |
| `mkdir` | Create a directory and missing parents | `path`, `mode` | `created` |

**Sessions.** Temporary storage on a node is addressed only by `session`, a
lowercase UUID the controller generates per run and batch, and `name`, a
relative path that cannot leave the session. The agent maps the session to
`<tmpdir>/file_transfer-<uuid>` under its own `tmpdir` setting, which
defaults to the Ruby temp dir and is set per node where `/tmp` is noexec.
The controller never computes a remote temp path. Every action checks with
`lstat` that the session directory and each component inside it is a real
directory owned by the agent's user, creates files 0600 and directories
0700, and opens with `O_NOFOLLOW`. The only removals are `cleanup` of one
session and the sweep inside `mktemp` of sessions untouched for
`stale_after` seconds. That setting defaults to one day and must exceed the
longest task timeout used against the node.

**Upload.** Agent detection, `stat` of the destination (an existing
directory receives the file inside it), `mktemp`, then `put` per chunk with
a running SHA-256. The last chunk carries `final`, `sha256`, `destination`,
and the source mode. The agent verifies the digest, applies the mode, and
renames the file onto the destination, copying beside it first when the
session is on another filesystem. `cleanup` runs in an ensure block on every
target where `mktemp` succeeded, gated by that target's `cleanup` option.
Directory uploads walk the local tree following links, `mkdir` per
directory, and reuse the one session.

**Download.** Agent detection, `stat` with checksum, then `get` by offset in
groups of `download-group-size` targets. Each reply is written to the local
file as it arrives through the block form of the RPC call. A target leaves
its group at `eof`. The local digest is compared with the one from `stat`.
Directory downloads `list` recursively and skip directories reached through
links. Downloads create no session.

**Chunk sizing.** Computed per batch from the broker's advertised
`max_payload`, the envelope size of a locally serialized empty request, and
the per-byte expansion from a second serialization, minus a 5 percent
reserve, capped by `chunk-size`. A guard on the client's publish compares
every payload with the limit before it leaves the controller. The reply
budget for downloads starts at a quarter of the request budget and is
measured from the first round's replies. Every reduction, after a guard hit,
a silent group, or a broker reconnect, is a prominent warning naming the
cause, the limit, the sizes before and after, the targets, and the remedy.

**Failures.** Status code 1 from the agent is a failure for that target on
every call. A target that fails a chunk or misses a chunk timeout gets an
error and is dropped from the rest of that transfer. Later chunks wait three
times the slowest chunk seen so far, bounded by `rpc-timeout`.

**Task arguments and files.** When task files or stdin arguments exceed the
shell agent's command limit, the shell path delivers them into a session
with `put` and runs the task from the session path. Small tasks keep the
inline path. The bolt_tasks path uses the same delivery only for OpenBolt's
apply helpers in Phase 5.

**Windows.** The DDL and protocol are platform neutral. Running a Ruby
script as an external agent needs a launcher on Windows, and the session
checks need an ACL equivalent to the mode checks. Parked until a Windows
Choria node is available.

### Config Changes

New options:
- `chunk-size` (Integer, default: 524288 = 512KB, minimum 16384) - Upper
  bound on the raw bytes per chunk. The effective size per batch is the
  payload limit minus the request envelope, capped by this value.
- `download-group-size` (Integer, default: 32, minimum 1) - Targets per
  download RPC round, which bounds reply volume to group size times chunk
  size

The `tmpdir` option keeps its meaning only for the shell path without the
file_transfer agent.

### Testing Strategy

1. Agent specs in its repository run the script as a subprocess against a
   temp root: every action's outcomes, session checks against links, foreign
   directories, and planted names, the sweep, exclusive creates, gaps,
   compression round trips, verify and move including across filesystems,
   and the final chunk retry
2. Transport unit tests with the stubbed RPC client: one session per batch
   with cleanup in the ensure path, chunk boundaries (empty, one chunk, many
   chunks), directory walks, grouping and dropping, results, and agent
   detection failing fast from the CLI and plan paths
3. Chunk sizing against a fake client wrapper: budget, guard overshoot,
   reply measurement, reductions, and warnings
4. One spec that loads the bundled DDL and validates a full-size chunk and
   the rejection cases through the client's validator
5. Integration tests against a real Choria cluster: a multi-GB file, a
   fleet-wide upload, a grouped download, a directory both ways, a
   destination on another filesystem than the temp root, an interrupted
   upload followed by a sweep, a `tmpdir` setting on a noexec host, and a
   policy denial

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

### Requirements

- Apply must not require the shell agent. It runs through the bolt_tasks
  agent and the Phase 4 file_transfer agent.

### What Needs Work: Apply Blocks

Apply blocks compile a Puppet catalog on the controller and apply it on the
target. Every step crosses the transport as a `run_task` call:

1. `apply_prep` runs the `puppet_library` hook task on targets without a
   Puppet agent, then the `apply_helpers::custom_facts` task with a plugin
   tarball argument.
2. `apply` runs the `apply_helpers::apply_catalog` task with the catalog and
   the plugin tarball as arguments. `get_resources` runs
   `apply_helpers::query_resources` the same way.

The helper tasks ship with OpenBolt in `libexec`. The bolt_tasks agent only
runs task files it downloads from the OpenVox/Puppet Server and verifies them
against the SHA-256 that OpenBolt supplies, so the helpers must also be served
by the server as the `apply_helpers` module with content identical to the
installed OpenBolt version. Task arguments above the bolt_tasks input limit
(the catalog and the plugin tarball) travel through the file_transfer agent,
and the helpers read them from that file.

Apply issues one batch per target because every target gets its own catalog,
and the transport serializes RPC calls. At fleet scale the transport must
broadcast the shared plugin tarball once, upload the catalogs per target, and
run and poll the helper task as one group. Otherwise apply on 10,000 nodes
serializes into hours.

### Investigation Needed

- How the `apply_helpers` module is published and versioned with OpenBolt
  releases.
- Whether the bolt_tasks agent needs the task metadata from the server in
  addition to the implementation files.
- Hiera lookups happen during catalog compilation on the controller. Confirm
  in testing.
- The `puppet_library` hook through bolt_tasks requires the
  `openvox_bootstrap` module on the OpenVox/Puppet Server.
- Confirm the Windows apply path fits within the PowerShell command length
  once arguments move to files.

### Testing Strategy

1. Simple apply block (single resource)
2. Apply with Hiera data
3. Apply with custom modules
4. Plan with mixed steps (run_command + run_task + apply)
5. Error handling in plans (catch_errors around Choria operations)
6. Parallel execution within plans

---

## Follow-up Work

Plan support in the Foreman integration follows Phase 5, once the plugins
gain plan execution.
