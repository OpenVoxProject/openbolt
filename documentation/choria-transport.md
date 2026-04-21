# Choria Transport

The Choria transport lets OpenBolt communicate with nodes via
[Choria's](https://choria.io/) NATS pub/sub messaging infrastructure instead
of SSH or WinRM. Rather than opening direct connections to each node, OpenBolt
publishes RPC requests to a NATS message broker, and agents running on target
nodes pick them up, execute the requested action, and reply.

Key components:
- **NATS broker**: Message middleware that routes requests and replies
- **Choria Server**: Runs on each managed node, hosts agents
- **Agents**: Plugins that perform actions (run commands, execute tasks, etc.)

The transport uses the `choria-mcorpc-support` Ruby gem as its client library.

For the project roadmap, see [choria-transport-plan.md](choria-transport-plan.md).
For developer documentation, see [choria-transport-dev.md](choria-transport-dev.md).
For test environment setup, see [choria-transport-testing.md](choria-transport-testing.md).

## Prerequisites

- A working Choria cluster with a NATS broker
- Choria Server running on each target node
- A Choria client config file on the OpenBolt controller
- At least one of the supported agents installed on target nodes:
  - **bolt_tasks** (ships with Puppet-enabled Choria setups)
  - **shell** (separate install, version 1.2.1 or later)

## Configuration

### Inventory setup

Transport and config options go under `config:` in your inventory file:

```yaml
# inventory.yaml
config:
  transport: choria
  choria:
    config-file: /home/user/.choriarc
targets:
  - uri: choria://node1.example.com
  - uri: choria://node2.example.com
```

Per-target overrides:

```yaml
targets:
  - uri: choria://node1.example.com
    config:
      choria:
        collective: production
        nats-servers:
          - nats://broker1:4222
          - nats://broker2:4222
```

If the config file is in one of the auto-detected locations (`~/.choriarc`,
`/etc/choria/client.conf`, `/etc/puppetlabs/mcollective/client.cfg`), you
can omit the `config-file` option.

### Target names must match Choria identities

The transport uses the target's hostname as a Choria identity filter. This
**must match the node's Choria identity exactly**, which is typically the
FQDN shown by `choria ping`.

If target names don't match, you'll see timeout errors. Use the full FQDN:

```yaml
targets:
  - uri: choria://node1.dc.example.com
```

If you want short names, use `name` with the `host` config to specify the
Choria identity separately:

```yaml
targets:
  - name: nodeA
    config:
      choria:
        host: node1.dc.example.com
```

### Config option reference

| Option | CLI Flag | Type | Default | Description |
|--------|----------|------|---------|-------------|
| `task-agent` | `--choria-task-agent` | String | `bolt_tasks` | Agent for task execution: `bolt_tasks` or `shell`. |
| `cleanup` | `--cleanup` | Boolean | `true` | Clean up temp directories after operations. Set to `false` for debugging. |
| `collective` | `--choria-collective` | String | (from config file) | Choria collective to route messages through. Per-target. |
| `command-timeout` | `--choria-command-timeout` | Integer | `60` | Seconds to wait for commands and scripts to complete. |
| `config-file` | `--choria-config-file` | String | (auto-detected) | Path to a Choria/MCollective client config file. |
| `host` | | String | (from URI) | Target's Choria identity (FQDN). Overrides the hostname from the URI. |
| `interpreters` | | Hash | (none) | File extension to interpreter mapping (e.g., `{".rb": "/usr/bin/ruby"}`). |
| `nats-connection-timeout` | `--nats-connection-timeout` | Integer | `30` | Seconds to wait for the TCP connection to the NATS broker. |
| `nats-servers` | `--nats-servers` | String or Array | (from config file) | NATS broker addresses in `nats://host:port` format (comma-separated for multiple). Multiple servers provide failover if a broker is unavailable. Overrides the config file. |
| `puppet-environment` | `--choria-puppet-environment` | String | `production` | Puppet environment for bolt_tasks file URIs. |
| `rpc-timeout` | `--choria-rpc-timeout` | Integer | `30` | Seconds to wait for replies to individual RPC calls. |
| `ssl-ca` | `--choria-ssl-ca` | String | (from config file) | CA certificate path for TLS. |
| `ssl-cert` | `--choria-ssl-cert` | String | (from config file) | Client certificate path for TLS. |
| `ssl-key` | `--choria-ssl-key` | String | (from config file) | Client private key path for TLS. |
| `task-timeout` | `--choria-task-timeout` | Integer | `300` | Seconds to wait for task execution to complete. |
| `tmpdir` | `--tmpdir` | String | `/tmp` or `C:\Windows\Temp` | Base path for temp directories on remote nodes. Must be absolute. |

**CLI flag precedence:** CLI flags provide default values that can be
overridden by inventory-level config (per-group or per-target). For example,
if a target has `collective: staging` in its inventory entry and
`--choria-collective production` is passed on the CLI, the inventory value
wins. For ad-hoc targets specified via `--targets` that aren't defined in an
inventory file, CLI flags take full effect.

For options that have corresponding values in the Choria config file
(`nats-servers`, `ssl-ca`/`ssl-cert`/`ssl-key`, and `collective`), the full
precedence from lowest to highest is: Choria config file < CLI flags <
inventory. All other options use OpenBolt-level defaults and are not affected by
the Choria config file.

**Timeout hierarchy:** Three levels of timeout control different things:
- `nats-connection-timeout` (30s): How long to wait for the initial TCP
  connection to the NATS broker
- `rpc-timeout` (30s): How long to wait for replies to each individual RPC
  call (discovery, status checks, etc.)
- `command-timeout` (60s) / `task-timeout` (300s): How long to wait for the
  entire operation (the full duration of the command or task)

**SSL options:** If you provide any of `ssl-ca`, `ssl-cert`, or `ssl-key`,
you must provide all three. Partial SSL configurations are rejected during
validation.

## Operations

### run_command

Requires the **shell agent** (>= 1.2.1) on target nodes.

```bash
bolt command run 'hostname -f' --targets node1.example.com,node2.example.com
```

Commands are started asynchronously on all targets in one RPC call, then
polled for completion. If a command exceeds `command-timeout`, the background
process is killed on the target node.

### run_script

Requires the **shell agent** (>= 1.2.1) on target nodes.

```bash
bolt script run ./check_disk.sh --targets node1.example.com
```

The script is uploaded to a temp directory on each target, made executable,
and run. Temp directories are cleaned up afterward (unless `cleanup: false`).

Interpreter support:

```yaml
choria:
  interpreters:
    ".rb": "/usr/bin/ruby"
    ".py": "/usr/bin/python3"
```

### run_task

Works with either the **bolt_tasks** or **shell** agent.

```bash
# Uses bolt_tasks by default (downloads from OpenVox/Puppet Server)
bolt task run facts --targets node1.example.com

# Use shell agent for local tasks not on the OpenVox/Puppet Server
bolt task run my_project::check --targets node1.example.com --choria-task-agent shell
```

Agent selection is deterministic with no automatic fallback. If the selected
agent is not available on a target, that target gets a clear error result.

### upload / download

Not yet supported. These will be implemented in Phase 4 with a new
chunked file-transfer agent. See the
[project plan](choria-transport-plan.md#phase-4-file-transfer-agent) for
details.

### connected?

Uses `rpcutil.ping`, which is built into every Choria node. No special
agents needed.

## Agent selection

### bolt_tasks (default)

The bolt_tasks agent ships with Puppet-enabled Choria setups. It downloads
task files from an OpenVox/Puppet Server and executes them. This means:

- Only `run_task` works (not `run_command` or `run_script`)
- Tasks must be installed on the OpenVox/Puppet Server
- Target nodes must be able to reach the OpenVox/Puppet Server

### shell (separate install)

The [shell agent](https://github.com/choria-plugins/shell-agent) is a
separate Choria plugin. Version 1.2.1 or later is required. It must be
installed on target nodes.

With the shell agent:
- `run_command` and `run_script` work
- `run_task` can use either agent (bolt_tasks by default, or shell with
  `--choria-task-agent shell`)

The shell agent DDL (required by the client library) is bundled with OpenBolt
and loaded automatically. No client-side setup is needed.

### Agent detection

On first contact with a target, the transport automatically discovers which
agents are installed and what OS the target is running. This happens
transparently. Agents below the required minimum version (e.g., shell < 1.2.1)
are excluded and treated as unavailable.

If a target is missing the required agent, it gets a clear error result with
a message suggesting what to install. Other targets in the same batch are
not affected.

### Installing the shell agent

The Choria plugin modules are not currently published on the Puppet Forge.
Install via Puppet by referencing the GitHub repository in your Puppetfile:

```ruby
mod 'mcollective_agent_shell',
  git: 'https://github.com/choria-plugins/shell-agent',
  ref: 'v1.2.1'
```

Deploy with r10k or Code Manager, then apply via Hiera:

```yaml
mcollective::plugin_classes:
  - mcollective_agent_shell
```

Restart `choria-server` on target nodes after installing.

For detailed installation instructions (including manual file copy), see
[choria-transport-testing.md](choria-transport-testing.md#shell-agent).

## Using bolt_tasks with an OpenVox/Puppet Server

### How bolt_tasks works

The bolt_tasks agent doesn't receive task files from OpenBolt directly. OpenBolt
sends file metadata (SHA256 hashes, OpenVox/Puppet Server URIs) and the agent
downloads the files from the OpenVox/Puppet Server itself. This means:

1. Task modules must be installed on the OpenVox/Puppet Server (in the environment's
   modulepath)
2. Task helper dependencies (like `ruby_task_helper`) must also be on the
   OpenVox/Puppet Server
3. Nodes must be able to reach the OpenVox/Puppet Server at their configured
   `puppet_server` address (default `puppet:8140`)

### Modulepath configuration

OpenBolt needs task metadata locally to build the file specs it sends to
bolt_tasks. If you're running on the primary server, the task modules already
exist on disk. Add all server-side module paths to OpenBolt's modulepath:

```yaml
# bolt-project.yaml
name: my_project
modulepath:
  - /etc/puppetlabs/code/environments/production/modules     # Environment modules
  - /etc/puppetlabs/code/modules                             # Base modules shared across environments
  - /opt/puppetlabs/puppet/modules                           # Puppet's vendored core modules (service, facts, etc.)
  - modules                                                  # OpenBolt Puppetfile-installed deps (ruby_task_helper, etc.)
```

Server-side paths are listed first so that OpenBolt reads the same module versions
that the bolt_tasks agent will download from the server. When using
`--choria-task-agent shell`, OpenBolt uploads task files directly, so local modules
should take precedence instead -- put `modules` first or omit the server paths.

OpenBolt also auto-injects its own internal paths (visible in `--log-level debug`
output): `bolt-modules` is prepended, and `.modules` plus the gem's built-in
modules directory are appended. These don't need to be specified manually.

**Important:** Setting `modulepath` replaces the default (`modules`), so you
must include `modules` explicitly. Without it, OpenBolt loses access to its
Puppetfile-installed modules (like `ruby_task_helper`, `facts`, etc.).

Or per-invocation:

```bash
bolt task run facts --targets node1,node2 \
  --modulepath "modules:/etc/puppetlabs/code/environments/production/modules:/etc/puppetlabs/code/modules:/opt/puppetlabs/puppet/modules"
```

### Installing task dependencies

Common tasks require helper modules on the OpenVox/Puppet Server:

```bash
# Required by most Ruby-based tasks (including 'facts')
sudo puppet module install puppetlabs-ruby_task_helper

# Required by Python-based tasks
sudo puppet module install puppetlabs-python_task_helper
```

Without these, you'll see download errors like:
```
bolt/choria-task-download-failed: ... ruby_task_helper/files/task_helper.rb: 404
```

### Using the shell agent for tasks

If a task is not available on the OpenVox/Puppet Server (e.g., it's a local project
task), set `task-agent` to `shell` to upload and execute it directly via
the shell agent, bypassing the OpenVox/Puppet Server entirely:

```yaml
# bolt-project.yaml
choria:
  task-agent: shell
```

Or per-invocation:

```bash
bolt task run my_project::check --targets node1 --choria-task-agent shell
```

When using `--choria-task-agent shell`, the OpenVox/Puppet Server requirement is bypassed
entirely. OpenBolt uploads task files directly via the shell agent, so only the
local modulepath matters.

## Limitations

1. **Upload and download not yet supported.** These will be implemented in a
   future release with a new file-transfer agent.

2. **Shell agent not installed by default.** Without it, only `run_task`
   (via bolt_tasks + OpenVox/Puppet Server) works. All other operations fail with a
   clear error message. Version 1.2.1 or later is required.

3. **bolt_tasks requires an OpenVox/Puppet Server.** The bolt_tasks agent downloads
   task files from the OpenVox/Puppet Server. Tasks not served by the OpenVox/Puppet Server
   will fail with an error suggesting `--choria-task-agent shell`.

4. **No streaming output.** All output is returned on completion, not streamed
   incrementally.

5. **No run-as support.** Choria uses its own identity model based on TLS
   certificates. There's no equivalent to SSH's `sudo` or `run-as`.

6. **No TTY support.** Interactive commands are not possible through Choria's
   messaging model.

7. **Timeout behavior differs by agent.** Shell agent processes are killed on
   timeout via `shell.kill`. bolt_tasks tasks continue running on the node
   after OpenBolt reports a timeout (bolt_tasks has no kill mechanism).

8. **File size limit for shell agent uploads.** When using the shell agent
   (`run_script`, `run_task` with `--choria-task-agent shell`), files are
   base64-encoded and sent as RPC messages. The maximum file size is limited
   by the NATS max message size (default 1MB, roughly 750KB effective after
   base64 overhead). Increase `plugin.choria.network.client_max_payload` in
   the Choria broker config for larger files. The bolt_tasks agent is not
   affected since it downloads files from the OpenVox/Puppet Server.

9. **POSIX targets need `base64` CLI for shell agent uploads.** The `base64`
   command (provided by coreutils on Linux, preinstalled on macOS) must be
   available on POSIX target nodes. On Windows, PowerShell handles this
   natively. The bolt_tasks agent is not affected.

10. **Shell agent job state accumulates on target nodes.** The shell agent
    stores job state in per-job directories under
    `/var/run/mcollective-shell/`. These are not automatically cleaned up
    after the process exits. Periodic manual cleanup may be necessary for
    long-running infrastructure.

11. **MCollective client library refuses to run as root.** Use a non-root
    user with a Puppet CA-signed certificate. See the
    [testing guide](choria-transport-testing.md#running-bolt-as-a-non-root-user)
    for setup instructions.
