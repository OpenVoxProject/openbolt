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
| Phase 4 | file_transfer >= 1.0.0 (separate install) | `upload`, `download` (any size, chunked) |
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
at a time, so memory use is bounded by the chunk size, not the file size. In
Phase 5 the bolt_tasks path also uses this agent to deliver the apply
helpers' arguments, which exceed that agent's input limit, as a file on the
target.

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
- The client side of the protocol is a library in the same module,
  `MCollective::Util::FileTransfer`, installed on client hosts as an
  MCollective util plugin (`client => true`). The transport is an adapter
  over it, so any Choria client can use the agent and OpenBolt carries none
  of the protocol.
- Options B and C are rejected. Fleet nodes cannot reach the subjects they
  need, and the Ruby NATS client OpenBolt uses has no JetStream support.
- Temporary storage on a node is one file beside the destination,
  `.file_transfer-<token>`, named by a token the controller chooses per
  file. The agent has no settings and no general delete action, only
  `abort` for that one file.
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

#### Option A: Base64 via Choria RPC

The simplest approach. File data is base64-encoded and sent as string
action inputs through standard Choria RPC calls. The agent decodes and
writes to disk. Compression was part of this option until 2026-09-22. Per
chunk it cut wire bytes but not round trips, and compressing a whole file
first cannot work for downloads, since each agent call is a fresh process
with no state. A user compresses a file before sending it when its size
matters.

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

The chunk is half the broker's advertised limit by default,
`message-data-size` in kibibytes to set it. The agent's design document
derives every layer of a request from the gem's code: with a 1 MiB limit
the largest content that fits is 568 KB on a single broker and 539 KB
through a federation broker with 200 targets of 253 byte names, so half
leaves room for longer identities and certificates, and more room at a
higher limit, since the fixed part of the envelope does not grow with
it. A direct request carries no identity list, so on a single broker the
envelope does not grow with the batch. The exact per-request computation
is parked on the agent repository's `exact-chunk-sizing` branch.

The client library reads the broker's advertised limit at run time:
- It reads `max_payload` from the NATS `INFO` the client received at
  connect, and assumes 1MB with a warning when the wrapper does not expose
  it
- A size guard at the wrapper's publish method compares every outgoing
  message, as serialized, against the limit before it is sent. An oversized
  request never leaves the controller. The targets of that call fail with
  `bolt/choria-payload-too-large` and a message naming a lower
  `message-data-size` as the remedy, and nothing is resent.
- Downloads cannot get that signal, because an oversized reply fails on the
  node and never reaches the controller. The request tells the agent the
  maximum reply size, the content a request could carry, since a reply
  carrying the same content weighs less than the request measured for it,
  and chunk requests use a short timeout derived from observed chunk
  latency. A target that does not answer is reported as not responding,
  without a retry.

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
- Zero encoding overhead on the data path (raw bytes over NATS)
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
| `put` | Write one chunk under a temporary name beside the destination, verify and rename on the last | `destination`, `token`, `offset`, `data`, `final`, `sha256`, `mode` | `bytes`, `size`, `sha256` |
| `abort` | Remove the temporary file of an upload that will not finish | `destination`, `token` | `removed` |
| `get` | Read one chunk | `path`, `offset`, `max_bytes` | `data`, `bytes`, `size` |
| `stat` | Describe a path | `path`, `checksum` | `exists`, `type`, `symlink`, `size`, `mode`, `mtime`, `sha256` |
| `list` | List every entry under a directory | `path`, `max_bytes` | `entries` |
| `mkdir` | Create a directory and missing parents | `path`, `mode` | none |

**Temporary names.** A file arrives on a node chunk by chunk under
`.file_transfer-<token>` beside its destination, the token being sixteen
hex characters the controller chooses per file, until its final chunk
verifies it and renames it into place. The agent has no settings and no
temp root. The first chunk creates the file exclusively at 0600, a later
chunk reopens it with `O_NOFOLLOW`, a put that fails after creating or
opening it removes it, and `abort` removes it for a controller that gave
up on the target. The only removal on a node is that one file.

**Upload.** Agent detection, `stat` of the destination (an existing
directory receives the file inside it), then `put` per chunk with the
destination and the token, once per distinct destination, with a running
SHA-256. The last chunk carries `final`, `sha256` and the source mode. The
agent verifies the digest through the open handle, applies the mode, and
renames the file onto the destination, which is beside it, so never a
copy. From an ensure the library sends `abort` to every target that was
sent a chunk and did not finish, skipping one whose agent refused a chunk
and removed the file itself. Directory uploads walk the local tree,
skipping links to directories, `mkdir` per directory, and a token per
file.

**Download.** Agent detection, `stat` with checksum, then `get` by offset in
rounds of as many targets as keep their replies under the broker's backlog.
Each reply is written to a temporary file beside its destination when its
round returns. A target is asked while the size its `stat` reported has
bytes beyond the offset, so the rounds end by that size alone. A reply
reaching past that size is cut at it, so a file that grew in the meantime
still verifies as the file that its `stat` described. The digest of what
was written is compared with the one from `stat`, and a copy that matches
gets the mode `stat` reported, with the owner's bits added, and is renamed
onto its destination, while one that does not is removed. A directory
download lists each target's whole tree, in rounds, under
`message-data-size`, makes each directory with the mode the target listed,
and skips directories reached through links. Downloads make nothing on the
nodes and no staging directory on the controller.

**Message data size.** Half the broker's advertised limit of file content
per request by default, `message-data-size` in kibibytes to set it. The
request's signed envelope, two base64 passes, and transport headers fit
beside that under the limit, which the agent's design document accounts
for at 1 MiB. A guard on the client's publish compares every payload with
the limit before it leaves the controller and fails the targets of a
refused call with the remedy in the message. A download round asks for
the same content, since a reply weighs less than a request, and so does a
directory listing, which the node refuses when its tree lists larger.

**Failures.** Status code 1 from the agent is a failure for that target on
every call. A target that fails a chunk or misses its reply window gets an
error and is dropped from the rest of that transfer. Every call waits
`file-transfer-timeout`, 300 seconds unless set, and never less than the
agent's DDL timeout, within which a target's server stops any request. The
wait ends a call on a target that will never answer, and one wait covers a
whole batch of chunk requests, so a slow link needs a longer wait or a
smaller batch.

**Task arguments and files.** The shell path does not use this agent. Its
task files and stdin arguments travel inside shell commands and stay bounded
by the shell agent's command limit, so each agent works on its own where a
deployment allows only one of them. The bolt_tasks path delivers OpenBolt's
apply helper arguments with a plain upload in Phase 5.

**Windows.** The DDL and protocol are platform neutral. Running a Ruby
script as an external agent needs a launcher on Windows, which the module
ships as `file_transfer.bat`, and the last component of a destination is
held to Windows name rules. A run on a Windows node is still owed.

### Config Changes

New options:
- `message-data-size` (Integer, no default, minimum 16) - The data one RPC
  call carries in kibibytes, the file content of a chunk and the most a
  directory listing may weigh. Without it, half the broker's message size
  limit, 512 at the NATS default of 1 MiB.
- `upload-batch-size` (Integer, no default, minimum 1) - Targets one chunk
  request is published to at once. Without it, the largest number that
  keeps one batch's copies under 256 MiB on the controller at the
  broker's limit.

A download round asks the largest number of targets that keeps one round
of replies under three quarters of the 64 MiB backlog the broker holds for
the controller's connection before closing it, with no option to change it.

The `tmpdir` option keeps its meaning only for the shell path without the
file_transfer agent.

### Testing Strategy

1. Agent specs in its repository run the script as a subprocess: every
   action's outcomes, the exclusive create beside the destination, the
   `O_NOFOLLOW` reopen, gaps, verify and rename, the removal on failure
   and through `abort`, and the Windows name rule in process
2. Transport unit tests with the stubbed RPC client: a token per file with
   abort for the targets that did not finish, chunk boundaries (empty, one
   chunk, many chunks), directory walks, grouping and dropping, results,
   and agent detection failing fast from the CLI and plan paths
3. Chunk sizing against a fake client wrapper: budget, guard refusal, and
   the warning for an unknown limit
4. One spec that loads the bundled DDL and validates a full-size chunk and
   the rejection cases through the client's validator
5. Integration tests against a real Choria cluster: a multi-GB file, a
   fleet-wide upload, a grouped download, a directory both ways, a
   destination whose parent is missing, an interrupted upload leaving
   `.file_transfer-<token>` beside the destination, and a policy denial

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

### Targets Without the Agent

A node that runs only the Choria server can execute nothing. The built-in
Go agents are read-only or configure the server, and every Ruby agent,
bolt_tasks and file_transfer included, needs the OpenVox agent's Ruby and
is installed by Choria's Puppet modules. `apply_prep` therefore cannot
install the agent through this transport.

Decision: a Choria target must already run the OpenVox agent and Choria's
Ruby agents. The transport detects the agent through discovery, skips the
install hook when it is present, and fails early with a message naming
the prerequisite when it is not. This is a documented parity exception,
and the file_transfer agent gets no execute action.

If users need `apply_prep` to install the agent, the path is a separate
`openvox_bootstrap` agent: a POSIX shell external agent with one hardcoded
action that installs the `openvox-agent` package from parameters, and a
status action, placed on the node outside Puppet (image, provisioning, or
a small noarch package). It needs a second piece before `apply_prep` can
finish: Choria's Ruby agents must appear after the install, shipped with
the agent by packaging or installed by the node's first Puppet run.

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
