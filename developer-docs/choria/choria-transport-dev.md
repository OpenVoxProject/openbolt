# Choria Transport: Developer Guide

This document orients developers to the Choria transport codebase. It covers
architecture, design patterns, threading, and data flow. For function-level
detail, see the code comments in each file.

For user-facing documentation, see the
[Choria transport user guide](https://docs.openvoxproject.org/openbolt/latest/choria-transport.html).
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
  once. The transport guards this with `@config_mutex` and checks
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
  command execution. Version 1.2.1+ required for the batched `statuses` action.
- **file_transfer**: A separate plugin
  ([overlookinfra/file_transfer-agent](https://github.com/overlookinfra/file_transfer-agent)),
  a Choria external agent written in Ruby. Provides `put`, `abort`,
  `get`, `stat`, `list`, and `mkdir` for chunked transfers with
  whole-file SHA-256 verification. Version 1.0.0+ required. The agent
  design, its semantics, and its own specs live in that repository. The
  client side of the protocol, `MCollective::Util::FileTransfer`, ships in
  the same module as client files and has to be installed on the controller
  (`mcollective_agent_file_transfer` with `client => true`). The transport
  is an adapter over it.

## File Layout

| File | Responsibility |
|------|---------------|
| `lib/bolt/transport/choria.rb` | Main transport class. Entry point for OpenBolt's executor. Batching, task routing, connectivity checks, and the single-target methods. |
| `lib/bolt/transport/choria/client.rb` | MCollective client configuration, RPC client creation, `rpc_request` pipeline. One-time setup, NATS/TLS overrides. |
| `lib/bolt/transport/choria/agent_discovery.rb` | Agent detection and OS discovery with per-target caching. |
| `lib/bolt/transport/choria/helpers.rb` | Shared utilities: `prepare_targets`, result builders, polling, security validators. |
| `lib/bolt/transport/choria/shell.rb` | Shell agent execution: commands, scripts, shell-path tasks. Batched polling architecture. |
| `lib/bolt/transport/choria/bolt_tasks.rb` | bolt_tasks agent execution: download, async start, status polling, stdout unwrapping. |
| `lib/bolt/transport/choria/file_transfer.rb` | upload and download through the file_transfer client library: targets to identities, options, outcomes to results, and the connection and logger the library calls back into. |
| `lib/bolt/transport/choria/command_builders.rb` | Platform-aware command generation for POSIX and Windows (PowerShell). |
| `lib/bolt/config/transport/choria.rb` | Config class: option declarations, defaults, validation. |
| `lib/bolt/config/transport/options.rb` | Shared option schema definitions (Choria entries added alongside other transports). |
| `lib/mcollective/agent/shell.ddl` | Bundled shell agent DDL for client-side validation. The file_transfer DDL is not bundled, since the agent module's client files bring it with the library. |

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

Agent versions are checked against `AGENT_MIN_VERSIONS` (e.g., shell >= 1.2.1).
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

On a POSIX node the directory that the `tmpdir` option names has to exist.
The tmpdir is created with `mkdir -m 700`, without `-p`, so a node without
that directory fails with `Could not make tmpdir`, like it does with the SSH
transport.

A preparation command that exits non-zero on a node is reported as the file
error the other transports report for that step. It has kind
`puppetlabs.tasks/task_file_error` and a message that starts with `Could not`,
for example `Could not make file '/tmp/bolt-choria-abc/script.sh' executable`.

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
  shared queue (message loss). Two concurrent clients are enough to break
  it. The mutex ensures only one RPC call is in flight at a
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
      shell_statuses(completed)        # 1 RPC call per 200 targets: shell.statuses -> output
    kill_timed_out_processes(...)       # sequential shell.kill calls (only on timeout)
    remove_job_dirs(pending)           # 1 RPC call per 40 targets: shell.run
```

Best-case total: 2 discovery + 1 start + 1 list + 1 statuses + 1 job directory
removal = **6 RPC calls**.

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
    upload_file_content: task            # 1 RPC call per chunk of each file
    shell_run: chmod                     # 1 RPC call
    upload_file_content: run file        # 1 RPC call per chunk
    shell_start(capable, run file)       # 1 RPC call
    wait_for_shell_results(pending, 300s)
      [loop every 1 second]:
        shell_list                       # 1 RPC call per round
        shell_statuses                   # 1 RPC call per 200 targets per round with completions
      remove_job_dirs                    # 1 RPC call per 40 targets
    cleanup_tmpdir                      # 1 RPC call
```

Best-case total (single file task): 2 discovery + 1 mkdir + 1 upload + 1 chmod
\+ 1 run file + 1 start + 1 list + 1 statuses + 1 job directory removal + 1
cleanup = **11 RPC calls**.

The task's command, with its arguments, goes to the nodes in a run file (see
Run files), so `shell.start` gets only a command that runs that file. Task
files and the run file go up in chunks that each fit the shell agent's 10,240
character command limit. The shell path does not use the file_transfer agent,
so each agent works on its own wherever a deployment allows only one of them.

### upload on N targets

```
batch_upload(N targets, source, destination)
  prepare_targets(targets)              # configure_client + 2 RPC calls
  Client#upload(source, destination, identities)   # the client library from here on
    file_transfer.stat(destination)     # 1 RPC call: directory or not
    [per chunk of message-data-size, 512 KiB by default]:
      file_transfer.put(destination, token, ...)   # 1 RPC call per landing path in batches of upload-batch-size, N copies published
    file_transfer.put(... final, sha256, mode)     # verify and rename into place
    file_transfer.abort(destination, token)        # 1 RPC call, only to the targets that did not finish
  one Bolt::Result per target from the outcome per identity
```

Every chunk is one RPC call whatever the target count, but the client
publishes one copy per target, so the controller's connection carries N
times the chunk. The call goes out to `upload-batch-size` targets at a
time through MCollective's batched requests, each batch with its own
publish and reply windows, so `file-transfer-timeout` has to cover one
batch on the wire rather than the whole fleet. Every request carries that
wait as its TTL, since a target drops a request older than its TTL and the
copies at the end of a batch arrive last. A directory adds one `mkdir` per
directory and the loop above per file. A link to a file is sent as the
file it points at, and a link to a directory is skipped with a warning, so
the walk cannot loop.

### download on N targets

```
batch_download(N targets, source, destination)
  prepare_targets(targets)              # configure_client + 2 RPC calls
  Client#download(source, directory per identity)   # the client library from here on
    file_transfer.stat(source, checksum)  # 1 RPC call: size and digest per target
    [per round of targets bounded by the broker's backlog, per offset of message-data-size]:
      file_transfer.get(source, offset, max_bytes)   # 1 RPC call, replies written when it returns
    verify digests, apply the reported modes, rename the copies into place
  one Bolt::Result per target from the outcome per identity
```

Each reply is written to a temporary file beside its destination under
`<destination>/<target>/`, which is renamed into place only after the
digest matches and gets the permission bits the target reported with the
owner's bits added under the umask, as net-scp gives a downloaded file,
and without the setuid, setgid and sticky bits. A copy that fails is
removed, and a directory already standing at the destination is a
per-target error rather than somewhere to hide the file. A directory
source is listed recursively first, then fetched file
by file from the targets that have it, each directory made with the
permission bits the target listed under the umask, special bits stripped.

What the node says about a download is checked before it is used. A reply
larger than the round asked for fails that target, a reply reaching past the
size the node reported for the file is cut at that size, and a reply from a
target whose size the rounds already covered is passed over.
A listed entry path becomes part of a local path only after every
component of it is checked to be one plain name in a valid encoding, so
it stays inside that target's download directory. A listing without the
size, digest and mode the download needs, or with a file the node could
not read for its digest, fails that target before anything is written for
it, and an entry that is neither a regular file nor a directory, a linked
directory included, is skipped with a warning. A directory is listed in
download batches of targets, each answering its whole tree under
`message-data-size`, and a target whose tree lists larger fails with the
agent's message. A reply that is not the shape the DDL promises fails
that one target and not the batch, except one the gem itself cannot
convert, with null or a string for data, which fails the whole call as
any exception in it does.

## Platform Support

OS is detected during agent discovery via the `os.family` fact.
`command_builders.rb` contains all platform-aware logic:

- **POSIX**: `/usr/bin/env` for env vars, `Shellwords.shellescape` for
  escaping, `printf '%s'` for stdin piping, `base64 -d` for file uploads,
  `mkdir -m 700` for temp dirs
- **Windows**: PowerShell `$env:` for env vars, single-quote doubling for
  escaping, here-strings for stdin, `[Convert]::FromBase64String` for uploads,
  `New-Item` for temp dirs with an ACL that leaves them open only to the
  agent's account and the Administrators group, `powershell.exe
  -EncodedCommand` for complex scripts

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
   - If the exit code is not 0 and the hash has no `_error`: adds one of kind
     `choria.tasks/task-error`
   - If wrapper error: returns `{"_error": {...}}.to_json` (a JSON **string**)
3. **`reply_task_status`** calls `.to_json` on that result:
   - Normal case: hash.to_json = proper JSON string
   - Wrapper error case: string.to_json = **double-encoded** JSON string
4. **OpenBolt receives** `result[:data][:stdout]` as a JSON string

The `unwrap_bolt_tasks_stdout` method handles this:
- Parses the outer JSON layer
- If that gives a string (double-encoding from the wrapper error case), returns
  the inner JSON string
- If that gives a hash with the agent's `choria.tasks/task-error`, takes the
  error out and returns what the task printed: the `_output` text when nothing
  else is left, the rest of the hash as JSON otherwise
- Returns any other stdout as-is. That covers stdout that is not JSON and a
  task that prints its own `_error`, since the agent adds its error only when
  the task has none
- `Bolt::Result.for_task` then does its own JSON parsing and builds the task
  error for a non-zero exit code, the way it does for the other transports

### wait_for_shell_results / shell_list / shell_statuses

The shell polling loop is the heart of asynchronous command execution:

**`wait_for_shell_results`** is the outer loop. It:
1. Sleeps `POLL_INTERVAL` (1 second)
2. Calls `shell_list` for one round of polling
3. Calls `shell_statuses` for any targets that completed this round
4. Tracks consecutive RPC failures (3 in a row = fail all remaining targets)
5. On timeout, calls `kill_timed_out_processes` to clean up remote processes
6. Calls `remove_job_dirs` for the jobs that finished (see Job directories)

**`shell_list`** does a single round:
1. Sends one batched `shell.list` RPC call to all remaining targets
2. For each target, matches its handle against the returned job list
3. Returns `[finished, failed, rpc_failed]`, where finished contains the
   targets whose process ended (status in `SHELL_DONE_STATUSES`: `stopped` or
   `failed`) and failed contains an error hash for each target whose poll failed

**`shell_statuses`** retrieves results for completed targets:
1. Sends one batched `shell.statuses` RPC call per `SHELL_STATUSES_BATCH_SIZE`
   (200) completed targets, with their handles. Every target answers for each
   handle of its call, so smaller calls keep each reply small.
2. Returns `{ target => output_hash }` with stdout, stderr, exitcode

Output is fetched immediately when targets complete, not deferred to after the
loop. This means completed targets have their results retrieved promptly.

### rpc_request

The central RPC helper through which every MCollective call flows. Key
behaviors:

**Serialization**: Acquires `@rpc_mutex` before any RPC call. See Threading
Model for why this is necessary.

**Error classification**: Splits results into three categories:
- **Success** (statuscode 0, or 1 when the caller passes `accept_aborted:
  true`): The agent responded. The `bolt_tasks` calls accept statuscode 1,
  which that agent answers for a task that ran and failed, and so does the
  ping behind `batch_connected?`. The status message of such a reply is
  returned under `:aborted`.
- **Agent error** (statuscode >= 2, or 1 for every other call): The action
  did not run or failed, as when an action policy denies the caller. Returned
  as failures with `bolt/choria-rpc-error`.
- **No response**: Target did not reply. Returned as failures with
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
4. Emit error results (via callback) for targets missing the required agent,
   and the discovery error for each target discovery failed for

Returns `[capable_targets, error_results]`. The caller proceeds with only
capable targets while error results are already emitted to the user.

### run_task_via_shell input_method handling

The shell path for task execution must handle four input methods:

- **`environment`**: Arguments become `PT_`-prefixed environment variables
  (via `envify_params`). Injected with `/usr/bin/env` on POSIX, `$env:` on
  Windows. Non-string values are JSON-serialized.
- **`stdin`**: Arguments are JSON-serialized and piped via `printf '%s'` on
  POSIX, PowerShell here-strings on Windows.
- **`both`**: Both mechanisms are used simultaneously.
- **`powershell`**: A `.ps1` task on Windows gets the arguments as named
  parameters, through the same snippets the WinRM transport uses
  (`Bolt::Shell::Powershell::Snippets`): base64 JSON that is splatted onto
  the parameters the script declares. Any other task runs without
  arguments, as it does with the SSH and WinRM transports.

**Why `printf '%s'` instead of `echo`**: `echo` interprets backslash escape
sequences on some platforms (e.g., `\n` becomes a newline). `printf '%s'`
passes the string through literally. This matters when task arguments contain
backslashes.

### The file_transfer client library

`MCollective::Util::FileTransfer` holds the whole transfer protocol: a
chunk of 512 KiB by default, half the Choria broker's 1 MiB limit, which
has no setting, a publish guard that refuses a request over that limit
before it leaves the controller, the
temporary file beside each destination, the chunk loops, download rounds,
directory walks, and the checks
on what a node says. Its README and the design document in the agent
repository describe it. The transport gives it three things and gets
outcomes back:

- **The client options and the RPC mutex**: the options this transport
  gives its own clients (`client_options`: verbose off, the broker
  timeout, the collective) and the transport's RPC mutex, from which the
  library builds its own connection, so a chunk call takes the same lock
  as every other RPC call in the process, one call at a time. The library
  builds its RPC clients itself, pins `threaded` to false, since the
  threaded publisher never joins its thread and an exception raised in it
  would never reach the caller, and finds the connector's wrapper on its
  own to prepend its publish guard.
- **A logger**: the transport's own, so the library's debug and warn
  lines land in OpenBolt's log.
- **Options** from the batch's first target (`file-transfer-timeout`,
  `message-data-size`, `upload-batch-size`), each left to the library's
  default when unset.

An outcome per identity becomes a `Bolt::Result` per target, with the
library's failure kinds mapped onto the transport's error kinds
(`FILE_TRANSFER_ERROR_KINDS`), so a chunk the broker's limit refuses is
`bolt/choria-payload-too-large` and a digest that differs is
`bolt/choria-checksum-mismatch`. A kind a later library adds is reported
as `bolt/choria-file-transfer-failed`, so a library update never breaks
the mapping. Two targets behind one identity get the same outcome of one
upload, and a download gives both the last one's directory, since the
library takes one directory per identity.

The library is required at run time from the Choria libdir, which loading
the client config put on the load path. When it is missing, every capable
target of the call gets a `bolt/choria-file-transfer-library` result naming
the module to apply.

## Architectural Decisions

### Async execution to avoid DDL timeouts

Both agents use asynchronous execution patterns (`bolt_tasks.run_no_wait`,
`shell.start`) instead of synchronous calls. The bolt_tasks DDL has a
hardcoded 60-second timeout on `run_and_wait`. The shell agent's `run` action
has a 180-second DDL timeout. Starting asynchronously and polling avoids
these limits entirely.

Synchronous `shell.run` is used for infrastructure operations (mkdir, chmod,
upload) that complete in sub-second times, where the DDL timeout is not a
concern.

### Fixed poll interval

Polling uses a fixed 1-second interval (`POLL_INTERVAL`). Exponential backoff
would add complexity without clear benefit. Each shell poll round makes 1
`shell.list` call, plus 1 `shell.statuses` call per 200 targets that finished
in that round. One second provides reasonable responsiveness without
excessive polling.

### Deterministic agent selection

Agent selection for `run_task` is explicit via the `task-agent` config
option (default `bolt_tasks`). There is no automatic fallback between agents.
If the selected agent is not available on a target, that target gets a clear
error. This is simpler and more predictable than a try-and-fallback approach.

### Batched shell polling

Shell polling uses `shell.list` + `shell.statuses` instead of per-handle
`shell.status` calls. This reduces RPC overhead from O(N) per round to O(1)
per target node, making it feasible at scale. Version 1.2.1 of the shell
agent is required because it is the first version with `shell.statuses`.

### Kill on timeout

When `wait_for_shell_results` times out, it kills background processes via
`shell.kill` to prevent orphans on target nodes. This does NOT apply to
bolt_tasks (which has no kill mechanism). The bolt_tasks agent eventually
times out its own subprocess based on the DDL timeout.

### Job directories

The shell agent's `start` action keeps a directory per job, with the command
and its output, under `/var/run/mcollective-shell` or
`C:/ProgramData/mcollective-shell`, and `shell.list` returns every one of
them. Only its `run` action removes its own directory. So once
`wait_for_shell_results` has the output of the jobs that finished,
`remove_job_dirs` deletes their directories through `shell.run`, on each
target whose `cleanup` option is on. One call contains the handles of up to
40 targets, each checked to be a UUID, and every target deletes only the one
it has. A job that timed out, or whose node stopped answering, keeps its
directory, since its process may still be running. Directories from earlier
OpenBolt versions, from runs with `cleanup` off and from other clients stay
until someone removes them on the node. A node whose
`plugin.shell.state_path` points elsewhere keeps its directories, since the
client cannot read that setting.

### Run files

A script or task command contains the script arguments, the env var values
and the task parameters, Sensitive ones included. The shell agent keeps every
`shell.start` command on disk in its job directory and returns it in
`shell.list` replies. So the shell path writes the command to `bolt_run.sh`,
or `bolt_run.ps1` on Windows, in the tmpdir through `shell.run`, and starts
only a command that runs that file. `shell.run` writes each upload command to
a job directory too, but it removes that directory when the command finishes.
The run file removes itself as soon as it starts. It stays in the tmpdir only
when its job never starts and `cleanup` is false.

On POSIX the run file's first line is `rm -f -- "$0"`, and `sh` keeps reading
the open file. A single command then replaces `sh` through `exec`, so
`shell.kill` reaches it. A task that takes its input from stdin stays a
pipeline under `sh`, since `exec` would run `printf` as its own process with
the task input in its arguments. For such a task `shell.kill` stops only `sh`.
On Windows the start command reads the file into memory and removes it before
it runs the content as a script block. A script block would hide a failing
last command from `powershell.exe`, so the content ends with
`if (-not $?) { exit 1 }`, which keeps the exit code the command would have
had on its own. `run_command` uploads nothing, so its command and env vars
still go through `shell.start`.

### Consecutive failure tracking

Both polling loops (`wait_for_shell_results` and `poll_task_status`) track
consecutive RPC failures. Three failures in a row triggers a fail-all for
remaining targets with `bolt/choria-poll-failed`. This prevents infinite
retry loops when the NATS broker goes down mid-operation.

## Scalability

The transport is built to run across thousands of nodes, potentially split
across a handful of collectives.

### Batch-only architecture

All operations use batch methods. The single-target methods, `run_command`,
`run_script`, `run_task`, `upload`, `download` and `connected?`, run their
batch counterparts with a batch of 1. This ensures the same code path handles
1 target and 10,000 targets. The remote transport calls `run_task` for its
run-on target. The single-target methods differ from a batch in 3 ways:

- `run_task` raises `Bolt::NoImplementationError` when no implementation of
  the task suits the target, like it does with the other transports. A batch
  reports that as the target's result.
- `run_script` and `run_task` raise `Bolt::Node::FileError` when a
  preparation step fails on the node, like they do with the other transports.
  A batch reports that as the target's result.
- `download` puts the file into the destination itself. A batch gives each
  target a directory of its own under the destination.

### O(N) identity filter setup

MCollective's `identity_filter` method uses array set union (`|`) per call,
making N calls O(N^2). For 10,000 targets, this is millions of operations.
The transport sets the identity filter array directly in O(N) and
pre-populates `@discovered_agents` with the same list to bypass broadcast
discovery.

### Batched polling

Shell polling uses one `shell.list` call per poll round, regardless of target
count, plus one `shell.statuses` call per 200 targets that finished in it.
bolt_tasks polling uses one `task_status` call per round with a shared
task_id.

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
- **Per-target options in batches:** Targets in one collective share the
  request-level options: the timeouts, the task agent, the interpreters, the
  Puppet environment, the shell tmpdir base and `cleanup` for the tmpdir. A
  batch reads them from its first target, so targets whose values differ get
  the first target's values. Batching by option values as well would serialize one batch per
  distinct set of values, which is far slower when the values vary per target.
- **Shell uploads in chunks:** `upload_file_content` embeds base64 file
  content in `shell.run` commands, and the shell agent DDL caps `command` at
  10,240 characters. So each call contains 6,000 bytes of raw content on POSIX
  targets and 2,000 on Windows, where the PowerShell wrapper re-encodes the
  command as UTF-16 base64, and a larger file takes 1 call per chunk.
  `run_command` sends its command and env vars in `shell.start`, so the limit
  still bounds them, and the shell agent's DDL validation refuses a command
  over it.
- **One publish per target:** the client publishes every request once per
  target, so a chunk to 1,000 targets leaves the controller 1,000 times.
  Uploads to a large fleet are bounded by the controller's connection to the
  broker, and `publish_timeout` is raised to `file-transfer-timeout` for
  those calls.
  The copies wait in nats-pure's outbound queue, bounded by count and not
  by bytes, until its flusher writes them, so a chunk goes to
  `upload-batch-size` targets at a time, 256 by default, which keeps one
  batch's copies under 256 MiB at the broker's 1 MiB limit.
  Nothing on the upload side meets a 64 MB limit: the broker buffers per
  connection, and each target's connection carries one copy per batch.
- **Download reply backlog:** every reply of a round lands on the
  controller's one broker connection, and nats-server closes a connection
  whose unread backlog passes 64 MiB after stalling the senders above
  three quarters of that. The library bounds a download round so that its
  replies at their wire size stay under the stall threshold, 48 targets
  at a 1 MiB limit, with no option to raise it. nats-pure's subscription
  buffer of the same size sits behind a callback that only queues
  replies, so it is not what a fleet-wide round meets.

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
| `spec/unit/transport/choria/file_transfer_spec.rb` | The adapter over the file_transfer client library against a stand-in for it: options, identities, outcomes to results, the connection and logger, the missing library |
| `spec/unit/transport/choria/command_builders_spec.rb` | POSIX/Windows command generation |
| `spec/unit/config/transport/choria_spec.rb` | Config options, defaults, validation |
| `spec/lib/bolt_spec/choria.rb` | Shared test helpers, config file writer, stub helpers |
| `spec/lib/bolt_spec/choria_file_transfer.rb` | The stand-in for the file_transfer client library, which the test suite does not have, with scripted outcomes |
| `spec/integration/transport/choria_spec.rb` | The container suite: the shared transport examples plus the agent, batch, cleanup, timeout and file transfer cases, against real nodes |
| `spec/Dockerfile.choria`, `spec/docker-compose.choria.yml`, `spec/fixtures/choria/` | The Choria broker and node containers, built the way the testing guide sets up a cluster |

### Mocking pattern

Tests use the real `choria-mcorpc-support` gem for `MCollective::Config`,
`MCollective::Util`, and `MCollective::RPC::Result`. The only stub of the
gem is `RPC::Client.new` (to avoid NATS TCP connections). The file transfer
specs also replace the client library, `MCollective::Util::FileTransfer`,
with the stand-in in `spec/lib/bolt_spec/choria_file_transfer.rb` and
answer its `require`. A fresh Tempfile
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

For a cluster set up by hand, see
[choria-transport-testing.md](choria-transport-testing.md).

### Container suite

`spec/integration/transport/choria_spec.rb` runs against a Choria broker and 3
nodes from `spec/docker-compose.choria.yml`. The image, `spec/Dockerfile.choria`,
installs the OpenVox agent and then applies the Puppetfile, Hiera data and site
manifest under `spec/fixtures/choria/`, the way the testing guide sets up a
cluster. `choria_node1` and `choria_node2` have the shell, file_transfer and
bolt_tasks agents, and `choria_node3` has only the agents Choria installs, for
the agent error cases. The host connects as `bolt.mcollective`, with the
file_transfer client library that `acceptance:choria:up` installs from the Forge
into `spec/fixtures/choria/modules` and with certificates it signs with the
fixture CA into `spec/fixtures/choria/ssl`. Git ignores both directories.

The suite runs the shared transport examples, then its own examples: a script's
environment variables, a node without the agents, batches, `connected?`,
`cleanup`, the command timeout and file transfers. It covers Linux nodes with
the shell and file_transfer agents. The stack has no OpenVox server, so
`task-agent` is `shell` and the bolt_tasks agent appears only in the agent error
cases.

```bash
bundle exec rake acceptance:choria        # start the containers and run the suite
bundle exec rake acceptance:choria:up     # start the containers
bundle exec rake ci:choria_transport      # run the suite
bundle exec rake acceptance:choria:logs   # print the container logs
bundle exec rake acceptance:choria:down   # remove the containers, certificates and module
```

`BOLT_CHORIA_FILE_TRANSFER_LIBDIR` points the suite at the `files` directory of
a file_transfer agent checkout instead of the installed module. The nodes keep
the Forge release the image installs. CI runs the suite in the
`choria_transport` job of `.github/workflows/tests.yaml`.
