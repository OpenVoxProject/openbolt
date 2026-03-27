# Choria Transport: Developer Guide

This document orients developers to the Choria transport codebase. It covers
architecture, design patterns, threading, and data flow. For function-level
detail, see the code comments in each file.

For user-facing documentation, see [choria-transport.md](choria-transport.md).
For the project roadmap, see [choria-transport-plan.md](choria-transport-plan.md).
For test environment setup, see [choria-transport-testing.md](choria-transport-testing.md).

## Architecture Overview

### Why Base, Not Simple

`Bolt::Transport::Choria` extends `Transport::Base` directly, not `Simple`.
The `Simple` base class assumes persistent connections and a shell abstraction
(open connection, run command, close connection). Choria doesn't work that
way. It's fire-and-forget messaging with no persistent connections. Every RPC
call creates a fresh client, publishes a request, waits for replies, and is
done.

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
- **DDLs are mandatory.** `MCollective::RPC::Client.new(agent)` loads the
  agent's DDL at construction time. DDLs for `rpcutil` and `bolt_tasks` ship
  with the `choria-mcorpc-support` gem. The shell DDL is bundled with OpenBolt
  at `lib/mcollective/agent/shell.ddl`.
- **MCollective::Config is a singleton.** `loadconfig` must only be called
  once. We guard this with `@config_mutex` and check
  `MCollective::Config.instance.configured`.

The Ruby library that implements this RPC client is the `choria-mcorpc-support`
gem, which provides `MCollective::RPC::Client`. Despite the MCollective name
(historical legacy), this is the current Choria client library.

### Key Agents

- **rpcutil**: Built into every Choria node. Provides `ping` and
  `agent_inventory` (what agents are installed).
- **bolt_tasks**: Ships with Puppet-enabled Choria setups. Downloads task files
  from an OpenVox/Puppet Server and executes them. Can only run tasks, not arbitrary
  commands.
- **shell**: A separate plugin
  ([choria-plugins/shell-agent](https://github.com/choria-plugins/shell-agent)).
  Provides synchronous (`run`) and asynchronous (`start`/`list`/`statuses`/`kill`)
  command execution. Version 1.2.0+ required for the batched `statuses` action.

## File Layout

| File | Responsibility |
|------|---------------|
| `lib/bolt/transport/choria.rb` | Main transport class. Entry point for OpenBolt's executor. Batching, task routing, connectivity checks. |
| `lib/bolt/transport/choria/client.rb` | MCollective client configuration, RPC client creation, `rpc_request` pipeline. One-time setup, NATS/TLS overrides. |
| `lib/bolt/transport/choria/agent_discovery.rb` | Agent detection and OS discovery with per-target caching. |
| `lib/bolt/transport/choria/helpers.rb` | Shared utilities: `prepare_targets`, result builders, polling, security validators. |
| `lib/bolt/transport/choria/shell.rb` | Shell agent execution: commands, scripts, shell-path tasks. Batched polling architecture. |
| `lib/bolt/transport/choria/bolt_tasks.rb` | bolt_tasks agent execution: download, async start, status polling, stdout unwrapping. |
| `lib/bolt/transport/choria/command_builders.rb` | Platform-aware command generation for POSIX and Windows (PowerShell). |
| `lib/bolt/config/transport/choria.rb` | Config class: option declarations, defaults, validation. |
| `lib/bolt/config/transport/options.rb` | Shared option schema definitions (Choria entries added alongside other transports). |
| `lib/mcollective/agent/shell.ddl` | Bundled shell agent DDL for client-side validation. |

See code comments in each file for function-level detail.

## Key Abstractions

### Agent Discovery and Caching

On first contact with a target, two RPC calls discover what's available:

1. `rpcutil.agent_inventory` returns the list of installed agents with versions
2. `rpcutil.get_fact(fact: 'os.family')` returns the OS family for platform dispatch

Results are cached in `@agent_cache`, a `Concurrent::Map` keyed by Choria
identity. Each entry stores `{ agents: [...], os: 'redhat'|'windows'|... }`.
The cache lives for the transport instance's lifetime. Non-responding targets
are not cached (intentional, to allow retry on transient failures).

Agent versions are checked against `AGENT_MIN_VERSIONS` (e.g., shell >= 1.2.0).
Agents below the minimum are excluded from the cache and logged as warnings.

### RPC Request Pipeline

All RPC calls flow through `rpc_request` in `client.rb`. This method:

1. Creates an `MCollective::RPC::Client` via `create_rpc_client`
2. Yields it to the caller's block
3. Splits results into successes and failures via `index_results_by_sender`
4. Handles error classification (see deep dive below)

The method is serialized by `@rpc_mutex` (see Threading Model).

### Batching Model

`batches(targets)` groups targets by their Choria collective. Each group runs
in its own OpenBolt batch thread with a single RPC client scope.

The `prepare_targets` helper combines the common setup pattern used by every
batch method:

1. `configure_client(target)` for one-time MCollective setup
2. `discover_agents(targets)` for agent detection
3. Partition targets into capable and incapable based on agent availability
4. Emit error results for incapable targets immediately
5. Return `[capable_targets, error_results]`

**Same-path trick for tmpdir:** All targets in a batch get the same tmpdir
path (e.g., `/tmp/bolt-choria-abc`). Since they're different machines, this
is fine, and it means every infrastructure command (mkdir, chmod, upload) can
be batched with identical arguments.

## Threading Model

OpenBolt runs batches in parallel threads sharing the same transport instance. The
transport handles this with:

- **`@config_mutex`**: Protects `configure_client` from concurrent access.
  Uses double-checked locking: the `@client_configured` flag is checked before
  and inside the lock for fast-path efficiency.

- **`@rpc_mutex`**: Serializes all RPC calls. This is necessary because
  MCollective's NATS connector is a PluginManager singleton with a single
  receive queue, and `MCollective::Client` uses a non-atomic
  `@@request_sequence` class variable for reply-to NATS subjects. Concurrent
  RPC calls cause response misrouting: threads can get duplicate sequence
  numbers (reply subject collision) and pop each other's messages from the
  shared queue (message loss). This was confirmed to break with just 2
  concurrent clients. The mutex ensures only one RPC call is in flight at a
  time while allowing non-RPC work (file I/O, result processing, cache
  lookups) to run in parallel across batch threads.

- **`@agent_cache`**: A `Concurrent::Map` (thread-safe without GIL
  dependency). Multiple batch threads write to it concurrently when targets
  span multiple collectives.

- **Per-target collective read**: `create_rpc_client` reads the collective
  from target options, not from shared transport state.

## Data Flow

### run_command on N targets

```
batch_command(N targets, "hostname")
  prepare_targets(targets)             # configure_client + 2 RPC calls: agent_inventory + get_fact
  shell_start(capable, cmd)            # 1 RPC call: shell.start -> N handles
  wait_for_shell_results(pending, 60s)
    [loop every 1 second]:
      shell_list(remaining)            # 1 RPC call: shell.list -> which are done?
      shell_statuses(completed)        # 1 RPC call: shell.statuses -> output for batch
    kill_timed_out_processes(...)       # sequential shell.kill calls (only on timeout)
```

Best-case total: 2 discovery + 1 start + 1 list + 1 statuses = **5 RPC calls**.

### run_task via bolt_tasks on N targets

```
batch_task(N targets, task, args)
  prepare_targets(targets)              # configure_client + 2 RPC calls
  run_task_via_bolt_tasks(capable, ...)
    bolt_tasks.download(file_specs)     # 1 RPC call (nodes download from OpenVox/Puppet Server)
    bolt_tasks.run_no_wait(task, args)  # 1 RPC call -> 1 shared task_id
    poll_task_status(targets, task_id)
      [loop every 1 second]:
        bolt_tasks.task_status(id)      # 1 RPC call per round
```

Best-case total: 2 discovery + 1 download + 1 run + 1 status = **5 RPC calls**.
The bolt_tasks path is inherently batched because task_status uses a shared task_id.

### run_task via shell on N targets

```
batch_task(N targets, task, args)
  prepare_targets(targets)              # configure_client + 2 RPC calls
  run_task_via_shell(capable, ...)
    shell_run: mkdir                     # 1 RPC call
    upload_file_content: task            # 1 RPC call per file
    shell_run: chmod                     # 1 RPC call
    shell_start(capable, cmd)            # 1 RPC call
    wait_for_shell_results(pending, 300s)
      [loop every 1 second]:
        shell_list                       # 1 RPC call per round
        shell_statuses                   # 1 RPC call per round with completions
    cleanup_tmpdir                      # 1 RPC call
```

Best-case total (single file task): 2 discovery + 1 mkdir + 1 upload + 1 chmod
\+ 1 start + 1 list + 1 statuses + 1 cleanup = **9 RPC calls**.

## Platform Support

OS is detected during agent discovery via the `os.family` fact.
`command_builders.rb` contains all platform-aware logic:

- **POSIX**: `/usr/bin/env` for env vars, `Shellwords.shellescape` for
  escaping, `printf '%s'` for stdin piping, `base64 -d` for file uploads,
  `mkdir -m 700` for temp dirs
- **Windows**: PowerShell `$env:` for env vars, single-quote doubling for
  escaping, here-strings for stdin, `[Convert]::FromBase64String` for uploads,
  `New-Item` for temp dirs, `powershell.exe -EncodedCommand` for complex scripts

`select_implementation` in `choria.rb` picks `.ps1` task files for Windows
targets and `.sh` for POSIX, supporting mixed-platform batches.

**Known gap (Phase 5):** `batch_script` does not handle `options[:pwsh_params]`
(PowerShell named parameter splatting for `.ps1` scripts). This option is only
reachable from the `run_script` plan function and YAML plan `script` steps,
which are not yet supported. When plan support is added, `batch_script` will
need a branch that builds a PowerShell splatting command (similar to
`Bolt::Shell::Powershell::Snippets.ps_task`) instead of passing positional
arguments.

## Key Function Deep Dives

### bolt_tasks stdout encoding chain (`unwrap_bolt_tasks_stdout`)

The bolt_tasks agent has a multi-layer encoding chain that requires careful
unwrapping:

1. **Task runs**, produces raw stdout
2. **`create_task_stdout`** (in `tasks_support.rb`) wraps it:
   - If valid JSON hash: returns the hash object
   - If valid JSON but not hash: wraps in `{"_output": raw_string}`
   - If not valid JSON: wraps in `{"_output": raw_string}`
   - If wrapper error: returns `{"_error": {...}}.to_json` (a JSON **string**)
3. **`reply_task_status`** calls `.to_json` on that result:
   - Normal case: hash.to_json = proper JSON string
   - Wrapper error case: string.to_json = **double-encoded** JSON string
4. **OpenBolt receives** `result[:data][:stdout]` as a JSON string

The `unwrap_bolt_tasks_stdout` method handles this:
- Parses the outer JSON layer
- If the result has only `_output` and/or `_error` keys (the wrapper's
  signature), extracts `_output` as the real stdout
- If `_output` is itself a JSON string (double-encoding from error case),
  unwraps one more layer
- Passes the unwrapped stdout to `Bolt::Result.for_task`, which does its own
  JSON parsing

Edge cases handled:
- Non-JSON stdout: returned as-is
- Task that legitimately returns `_output` keys alongside other keys: detected
  by checking for extra keys beyond the wrapper's signature
- Zero exit code with `_error`: the task itself reported the error, don't unwrap

### wait_for_shell_results / shell_list / shell_statuses

The shell polling loop is the heart of asynchronous command execution:

**`wait_for_shell_results`** is the outer loop. It:
1. Sleeps `POLL_INTERVAL` (1 second)
2. Calls `shell_list` for one round of polling
3. Calls `shell_statuses` for any targets that completed this round
4. Tracks consecutive RPC failures (3 in a row = fail all remaining targets)
5. On timeout, calls `kill_timed_out_processes` to clean up remote processes

**`shell_list`** does a single round:
1. Sends one batched `shell.list` RPC call to all remaining targets
2. For each target, matches its handle against the returned job list
3. Returns `[done_hash, rpc_failed_boolean]` where done contains completed
   targets (status in `SHELL_DONE_STATUSES`: `stopped` or `failed`)

**`shell_statuses`** retrieves results for completed targets:
1. Sends one batched `shell.statuses` RPC call with all completed handles
2. Returns `{ target => output_hash }` with stdout, stderr, exitcode

Output is fetched immediately when targets complete, not deferred to after the
loop. This means completed targets have their results retrieved promptly.

### rpc_request

The central RPC helper through which every MCollective call flows. Key
behaviors:

**Serialization**: Acquires `@rpc_mutex` before any RPC call. See Threading
Model for why this is necessary.

**Error classification**: Splits results into three categories:
- **Success** (statuscode 0 or 1): The agent responded. Statuscode 1 means
  "application error but action completed" (the task ran but had issues).
- **Agent error** (statuscode >= 2): The agent itself had a problem. Returned
  as failures with `bolt/choria-agent-error`.
- **No response**: Target didn't reply. Returned as failures with
  `bolt/choria-no-response`.

**Absorption of StandardError**: If the RPC call raises a `StandardError`
(but not a `Bolt::Error`, which is re-raised), the error is absorbed and all
targets are returned as failures with `bolt/choria-rpc-failed`. This prevents
a single NATS hiccup from crashing the entire batch.

### prepare_targets

The common setup pattern used by every batch method. Combines four steps into
one call:

1. `configure_client(target)` for one-time MCollective setup
2. `discover_agents(targets)` for agent detection (cached after first call)
3. Partition targets by agent availability using `has_agent?`
4. Emit error results (via callback) for targets missing the required agent

Returns `[capable_targets, error_results]`. The caller proceeds with only
capable targets while error results are already emitted to the user.

### run_task_via_shell input_method handling

The shell path for task execution must handle three input methods:

- **`environment`**: Arguments become `PT_`-prefixed environment variables
  (via `envify_params`). Injected with `/usr/bin/env` on POSIX, `$env:` on
  Windows. Non-string values are JSON-serialized.
- **`stdin`**: Arguments are JSON-serialized and piped via `printf '%s'` on
  POSIX, PowerShell here-strings on Windows.
- **`both`**: Both mechanisms are used simultaneously.

**Why `printf '%s'` instead of `echo`**: `echo` interprets backslash escape
sequences on some platforms (e.g., `\n` becomes a newline). `printf '%s'`
passes the string through literally. This matters when task arguments contain
backslashes.

## Architectural Decisions

### Async execution to avoid DDL timeouts

Both agents use asynchronous execution patterns (`bolt_tasks.run_no_wait`,
`shell.start`) instead of synchronous calls. The bolt_tasks DDL has a
hardcoded 60-second timeout on `run_and_wait`. The shell agent's `run` action
has a 180-second DDL timeout. By starting asynchronously and polling, we avoid
these limits entirely.

Synchronous `shell.run` is used for infrastructure operations (mkdir, chmod,
upload) that complete in sub-second times, where the DDL timeout is not a
concern.

### Fixed poll interval

Polling uses a fixed 1-second interval (`POLL_INTERVAL`). Exponential backoff
was considered but adds complexity without clear benefit. Each poll round is a
single RPC call regardless of target count, so the broker load is constant.
One second provides reasonable responsiveness without excessive polling.

### Deterministic agent selection

Agent selection for `run_task` is explicit via the `task-agent` config
option (default `bolt_tasks`). There is no automatic fallback between agents.
If the selected agent is not available on a target, that target gets a clear
error. This is simpler and more predictable than a try-and-fallback approach.

### Batched shell polling

Shell polling uses `shell.list` + `shell.statuses` instead of per-handle
`shell.status` calls. This reduces RPC overhead from O(N) per round to O(1)
per target node, making it feasible at scale. This is why version 1.2.0
of the shell agent is required, since this is the version version to include
`shell.statuses`.

### Kill on timeout

When `wait_for_shell_results` times out, it kills background processes via
`shell.kill` to prevent orphans on target nodes. This does NOT apply to
bolt_tasks (which has no kill mechanism). The bolt_tasks agent eventually
times out its own subprocess based on the DDL timeout.

### Consecutive failure tracking

Both polling loops (`wait_for_shell_results` and `poll_task_status`) track
consecutive RPC failures. Three failures in a row triggers a fail-all for
remaining targets with `bolt/choria-poll-failed`. This prevents infinite
retry loops when the NATS broker goes down mid-operation.

## Scalability

This code was written to ensure scalability when running across thousands
and thousands of nodes, potentially split across a handful of collectives.

### Batch-only architecture

All operations use batch methods. Single-target `run_task`, `run_command`,
`run_script`, and `connected?` delegate to their batch counterparts. This
ensures the same code path handles 1 target and 10,000 targets.

### O(N) identity filter setup

MCollective's `identity_filter` method uses array set union (`|`) per call,
making N calls O(N^2). For 10,000 targets, this is millions of operations.
The transport sets the identity filter array directly in O(N) and
pre-populates `@discovered_agents` with the same list to bypass broadcast
discovery.

### Batched polling

Shell polling uses one `shell.list` + one `shell.statuses` call per poll
round, regardless of target count. bolt_tasks polling uses one `task_status`
call per round with a shared task_id.

### OpenBolt concurrency vs. Choria concurrency

OpenBolt's `--concurrency` setting controls parallel target processing in
SSH/WinRM transports. This does not apply to Choria. The Choria transport
handles its own concurrency: `batches()` groups targets by collective
(typically 1 group), and each batch uses MCollective's native multi-node RPC.

### Known scaling limitations

- **Shell agent at extreme scale (5,000+ targets):** Even with batched
  polling, 5,000 shell targets create significant polling overhead. The
  bolt_tasks path is preferred for large deployments.
- **Agent discovery for offline nodes:** Non-responding targets are not cached
  (to allow retry), so each operation re-queries offline nodes. At 10,000
  targets with many offline, this adds discovery overhead.
- **Per-target options in batches:** Batch methods use `targets.first.options`
  for shared settings (timeout, tmpdir, cleanup). Per-target option differences
  within a batch are silently ignored. This is inherent to the batch execution
  model.
- **Base64 upload size:** The `upload_file_content` method sends files
  in a single NATS message. After base64 encoding (~33% expansion) and RPC
  overhead, the max raw file size is roughly 700-750KB with the default 1MB
  message limit. This will be addressed in Phase 4 with chunked file transfer.

## Testing

### Test file layout

| File | Coverage |
|------|---------|
| `spec/unit/transport/choria_spec.rb` | Main transport: batching, task routing, connectivity |
| `spec/unit/transport/choria/client_spec.rb` | Client config, RPC client creation |
| `spec/unit/transport/choria/agent_discovery_spec.rb` | Agent detection, caching, version checks |
| `spec/unit/transport/choria/helpers_spec.rb` | RPC pipeline, prepare_targets, security validators |
| `spec/unit/transport/choria/shell_spec.rb` | Shell execution, polling, uploads, cleanup |
| `spec/unit/transport/choria/bolt_tasks_spec.rb` | bolt_tasks execution, polling, stdout unwrapping |
| `spec/unit/transport/choria/command_builders_spec.rb` | POSIX/Windows command generation |
| `spec/unit/config/transport/choria_spec.rb` | Config options, defaults, validation |
| `spec/lib/bolt_spec/choria.rb` | Shared test helpers, config file writer, stub helpers |

### Mocking pattern

Tests use the real `choria-mcorpc-support` gem for `MCollective::Config`,
`MCollective::Util`, and `MCollective::RPC::Result`. The only MCollective
stub is `RPC::Client.new` (to avoid NATS TCP connections). A fresh Tempfile
config is written per test via `write_choria_config`. The standard pattern:

```ruby
# In bolt_spec/choria.rb shared context:
let(:mock_rpc_client) { double('MCollective::RPC::Client') }

before(:each) do
  @choria_config_file = write_choria_config
  MCollective::Config.instance.set_config_defaults(@choria_config_file.path)
  allow(MCollective::RPC::Client).to receive(:new).and_return(mock_rpc_client)
end
```

A plain `double` is used (not `instance_double`) because the real RPC client
dispatches agent actions via `method_missing`.

### Running tests

```bash
bundle exec rspec spec/unit/transport/choria/
bundle exec rspec spec/unit/config/transport/choria_spec.rb
```

For the full suite:

```bash
bundle exec rspec spec/unit/transport/choria/ spec/unit/config/transport/choria_spec.rb
```

For manual/integration testing, see
[choria-transport-testing.md](choria-transport-testing.md).
