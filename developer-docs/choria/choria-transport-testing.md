# Choria Transport: Test Environment Setup

A guide for setting up a Choria test environment alongside an existing OpenVox
Puppet installation, and verifying all Choria transport functionality in OpenBolt.

For configuration reference, see [choria-transport.md](choria-transport.md).
For the project roadmap, see [choria-transport-plan.md](choria-transport-plan.md).
For developer documentation, see [choria-transport-dev.md](choria-transport-dev.md).

## Prerequisites

- A primary server (also the OpenBolt controller) with OpenBolt installed
- Two or more remote nodes running Choria server
- The remote nodes start with the default agent set: `choria_util`, `discovery`,
  `filemgr`, `package`, `puppet`, `rpcutil`, `scout`, `service`
- Neither `bolt_tasks` nor `shell` agents are installed initially
- A working OpenVox Puppet installation (for TLS certificates)

## Installing development changes on the primary

The packaged OpenBolt lives at `/opt/puppetlabs/bolt/`. The gem's lib directory
is at:

```
/opt/puppetlabs/bolt/lib/ruby/gems/<ruby-version>/gems/openbolt-<version>/lib
```

To test changes without rebuilding the package, just
overwrite the lib directory. If it gets messed up, reinstall the package.

### Copy the lib directory to the primary

```bash
DEV=/path/to/openbolt   # your local checkout
PRIMARY=user@primary.example.com
BOLT_GEM=/opt/puppetlabs/bolt/lib/ruby/gems/<ruby-version>/gems/openbolt-<version>/lib

rsync -av $DEV/lib/ $PRIMARY:/tmp/openbolt-lib/
ssh $PRIMARY "sudo rsync -av /tmp/openbolt-lib/ $BOLT_GEM/"
```

### Install the choria-mcorpc-support gem

The Choria transport depends on `choria-mcorpc-support ~> 2.26`. This gem is
included in OpenBolt 5.4.0. But when testing against and older version, install it into the packaged
OpenBolt's gem environment:

```bash
sudo /opt/puppetlabs/bolt/bin/gem install choria-mcorpc-support --version '~> 2.26' --no-document
```

Verify it's loadable:

```bash
/opt/puppetlabs/bolt/bin/ruby -e "require 'mcollective'; puts 'choria-mcorpc-support loaded OK'"
```

### Verify the transport loads

```bash
/opt/puppetlabs/bolt/bin/ruby -e "
  require 'bolt/transport/choria'
  require 'bolt/config/transport/choria'
  puts 'Choria transport loaded OK'
  puts 'Config options: ' + Bolt::Config::Transport::Choria::OPTIONS.join(', ')
"
```

## Choria client configuration

The OpenBolt controller needs a Choria client config to connect to the NATS broker.
The MCollective client library refuses to run as root, so OpenBolt must be run as a
regular user.

MCollective looks for client config files in this order (first readable wins):

1. `~/.choriarc`
2. `~/.mcollective`
3. `/etc/choria/client.conf`
4. `/etc/puppetlabs/mcollective/client.cfg`

### Generate a client certificate

The user running OpenBolt needs a certificate signed by the Puppet CA. For non-root
users, MCollective resolves the certname as `<username>.mcollective` by default.
Generate a matching certificate on the primary server:

```bash
sudo puppetserver ca generate --certname <username>.mcollective
```

Copy the cert, key, and CA to the user's home directory:

```bash
mkdir -p ~/.puppetlabs/etc/puppet/ssl/certs ~/.puppetlabs/etc/puppet/ssl/private_keys
sudo cp /etc/puppetlabs/puppet/ssl/certs/<username>.mcollective.pem \
  ~/.puppetlabs/etc/puppet/ssl/certs/
sudo cp /etc/puppetlabs/puppet/ssl/private_keys/<username>.mcollective.pem \
  ~/.puppetlabs/etc/puppet/ssl/private_keys/
sudo cp /etc/puppetlabs/puppet/ssl/certs/ca.pem \
  ~/.puppetlabs/etc/puppet/ssl/certs/
sudo chown -R $(whoami) ~/.puppetlabs
chmod 600 ~/.puppetlabs/etc/puppet/ssl/private_keys/*.pem
```

### Set up `~/.choriarc`

Create `~/.choriarc` with the NATS broker address and cert paths. Replace
`primary.example.com` with your primary server's FQDN and `<username>` with
your OS username throughout:

```ini
collectives = mcollective
main_collective = mcollective
connector = nats
identity = <username>.mcollective
libdir = /opt/puppetlabs/mcollective/plugins
logger_type = console
loglevel = warn
securityprovider = choria
plugin.choria.middleware_hosts = nats://primary.example.com:4222
plugin.security.provider = file
plugin.security.file.certificate = ~/.puppetlabs/etc/puppet/ssl/certs/<username>.mcollective.pem
plugin.security.file.key = ~/.puppetlabs/etc/puppet/ssl/private_keys/<username>.mcollective.pem
plugin.security.file.ca = ~/.puppetlabs/etc/puppet/ssl/certs/ca.pem
```

### Verify Choria connectivity

```bash
choria ping
choria rpc rpcutil agent_inventory
```

### Running OpenBolt

The packaged OpenBolt is at `/opt/puppetlabs/bolt/bin/bolt`, wrapped by
`/opt/puppetlabs/bin/bolt`.
Use config files and OpenBolt inventory config rather than environment variables
for MCollective settings.

## Test inventory setup

Create a test project directory:

```bash
mkdir -p ~/choria-test && cd ~/choria-test
```

```yaml
# bolt-project.yaml
---
name: choria_test
modulepath:
  - /etc/puppetlabs/code/environments/production/modules     # Environment modules (tasks for bolt_tasks to download)
  - /etc/puppetlabs/code/modules                             # Base modules shared across environments
  - /opt/puppetlabs/puppet/modules                           # Puppet's vendored core modules (service, facts, etc.)
  - modules                                                  # OpenBolt Puppetfile-installed deps (ruby_task_helper, etc.)
```

OpenBolt needs local access to task metadata to know which files to tell the
bolt_tasks agent to download. The server-side module paths are listed first
so that OpenBolt reads the same module versions that the bolt_tasks agent will
actually download from the server. The local `modules` directory comes last
as a fallback for Puppetfile-installed dependencies. When using
`--choria-task-agent shell`, OpenBolt uploads files directly, so local modules should
take precedence instead — put `modules` first or omit the server paths.

Task helper dependencies like `puppetlabs-ruby_task_helper` must also be
installed on the server. Without them, bolt_tasks will fail with 404 errors
when downloading task files.

OpenBolt also auto-injects its own internal paths (visible in `--log-level debug`
output): `bolt-modules` is prepended, and `.modules` plus the gem's built-in
modules directory are appended. These don't need to be specified manually.

```yaml
# inventory.yaml
---
config:
  transport: choria
targets:
  - name: agent1
    config:
      choria:
        host: nodeA.example.com
  - name: agent2
    config:
      choria:
        host: nodeB.example.com
```

Transport and transport config go under `config:` in `inventory.yaml` (not in
`bolt-project.yaml`). The `name` is a short alias for use in OpenBolt commands,
and `host` is the actual Choria identity (FQDN shown by `choria ping`).

Since `~/.choriarc` is auto-detected, no `config-file` setting is needed
in the inventory.

### Target names must match Choria identities

Target URIs must use the exact Choria identity (typically the FQDN shown by
`choria ping`). Mismatched names cause timeout errors. See
[choria-transport.md](choria-transport.md#target-names-must-match-choria-identities)
for details and workarounds using `name` with `host` config.

## Setting up Choria infrastructure via Puppet

The `choria` Puppet module manages the Choria server, broker, and MCO Ruby
compatibility layer on your nodes. The `bolt_tasks` and `shell` agents are
Ruby MCollective agents that run through Choria's MCO compatibility shim.

### Puppetfile

Some of the agent modules are on the Forge, but they are no longer being updated there. Add them from GitHub:

```ruby
# Puppetfile (in the environment, e.g. production)
mod 'choria-choria', :latest
mod 'choria-mcollective', :latest
mod 'choria-mcollective_choria', :latest
mod 'mcollective_agent_shell',
  git: 'https://github.com/choria-plugins/shell-agent',
  ref: '1.2.1'
```

The shell agent requires version 1.2.1 or later (for the batched `statuses`
action). The `bolt_tasks` agent is included in a standard Choria install and
does not need a separate Puppetfile entry.

Deploy with r10k:

```bash
sudo /opt/puppetlabs/puppet/bin/r10k puppetfile install \
  --puppetfile /path/to/Puppetfile \
  --moduledir /etc/puppetlabs/code/environments/production/modules
```

### Hiera configuration

Set up the environment-level hiera config:

```yaml
# hiera.yaml (in the environment directory)
---
version: 5
defaults:
  datadir: data
  data_hash: yaml_data
hierarchy:
  - name: "Per-node data"
    path: "nodes/%{trusted.certname}.yaml"
  - name: "Common data"
    paths:
      - "common.yaml"
```

Common data applied to all nodes. You don't have to use this exact configuration, (i.e. you might want to use SRV instead, different configs for different nodes, etc.):

```yaml
# data/common.yaml
choria::manage_package_repo: true
choria::server: true

choria::server_config:
  plugin.choria.puppetserver_host: "primary.example.com"
  plugin.choria.puppetserver_port: 8140
  plugin.choria.puppetca_host: "primary.example.com"
  plugin.choria.puppetca_port: 8140
  plugin.choria.middleware_hosts: "primary.example.com:4222"
  plugin.choria.use_srv: false

# Allow all callers for testing. Restrict in production.
mcollective::site_policies:
  - action: "allow"
    callers: "/.*/"
    actions: "*"
    facts: "*"
    classes: "*"

mcollective::client: true
mcollective_choria::config:
  security.certname_whitelist: "/\\.mcollective$/, /.*/"

mcollective::client_config:
  plugin.security.provider: "file"
  plugin.security.file.certificate: "/etc/puppetlabs/puppet/ssl/certs/%{trusted.certname}.pem"
  plugin.security.file.key: "/etc/puppetlabs/puppet/ssl/private_keys/%{trusted.certname}.pem"
  plugin.security.file.ca: "/etc/puppetlabs/puppet/ssl/certs/ca.pem"

mcollective::plugin_classes:
  - mcollective_agent_bolt_tasks
  - mcollective_agent_shell
```

Per-node data for the primary (enables the NATS broker):

```yaml
# data/nodes/<primary-certname>.yaml
choria::broker::network_broker: true
```

### Site manifest

Again, you don't need to set it up this way directly, but an easy manifest for working with just a handful of nodes.

```puppet
# site.pp
node "primary.example.com" {
  include choria
  include choria::broker
}

node default {
  include choria
  file { '/root/.choria':
    ensure  => file,
    content => "plugin.security.provider = puppet\nplugin.security.certname = ${trusted['certname']}\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
  }
}
```

### Apply and verify

Run Puppet on all nodes:

```bash
ssh nodeA.example.com 'sudo puppet agent -t'
ssh nodeB.example.com 'sudo puppet agent -t'
```

Verify agents are loaded:

```bash
choria rpc rpcutil agent_inventory -I nodeA.example.com
```

The agent list should include `bolt_tasks` and `shell`.

**Client-side DDLs:** The `bolt_tasks` DDL comes from the
`choria-mcorpc-support` gem (included in OpenBolt 5.4.0). The `shell` DDL is
bundled with OpenBolt and preloaded automatically. No manual DDL installation
is needed on the OpenBolt controller.

### Removing agents for testing

To test downgrade scenarios (verifying error messages when agents are missing),
remove agents from `mcollective::plugin_classes` in Hiera and set absent:

```yaml
mcollective_agent_shell::ensure: absent
```

Run Puppet on the node, then restart Choria server:

```bash
ssh nodeA.example.com 'sudo puppet agent -t && sudo systemctl restart choria-server'
```

Verify removal:

```bash
choria rpc rpcutil agent_inventory -I nodeA.example.com
```

OpenBolt caches agent lists per target for the transport's lifetime, so start a
fresh `bolt` command after changing agents (don't re-run within the same plan).

## Test cases

### Connectivity (no agents required)

```bash
bolt inventory show --targets nodeA.example.com
```

This doesn't require any special agents. It should show the target config.

### No task agents installed

Both nodes have only the default Choria agents. Neither `bolt_tasks` nor
`shell` is installed. Every operation that needs them should fail with a
clear, per-node error.

**run_command (needs shell agent)**

```bash
bolt command run 'whoami' --targets nodeA.example.com,nodeB.example.com
```

Expected: Both nodes fail with an error like:
```
The 'shell' agent is not available on nodeA.example.com.
```

Verify the error names the specific target, not a generic failure.

**run_script (needs shell agent)**

```bash
echo '#!/bin/bash
echo "hello from $(hostname)"' > /tmp/test.sh

bolt script run /tmp/test.sh --targets nodeA.example.com,nodeB.example.com
```

Expected: Same shell agent error.

**run_task (needs bolt_tasks or shell)**

```bash
bolt task run facts --targets nodeA.example.com,nodeB.example.com
```

Expected: Both nodes fail with an error like:
```
The 'bolt_tasks' agent is not available on nodeA.example.com.
Install either the bolt_tasks or shell agent on target nodes to run tasks via Choria.
```

**upload/download (not yet supported)**

```bash
bolt file upload /tmp/test.sh /tmp/test_remote.sh --targets nodeA.example.com
bolt file download /etc/hostname /tmp/downloaded/ --targets nodeA.example.com
```

Expected: Both fail with `The Choria transport does not yet support upload/download.`

### bolt_tasks agent only

Install `bolt_tasks` on **both nodes** (see "Installing agents" above).

**run_task with an OpenVox/Puppet Server task**

```bash
bolt task run facts --targets nodeA.example.com,nodeB.example.com
```

Expected: Succeeds on both nodes. The bolt_tasks agent downloads the `facts`
task from the OpenVox/Puppet Server and executes it.

Note: This requires the OpenVox/Puppet Server to be accessible from the remote nodes
at their configured `puppet_server` (default `puppet:8140`) and the task
module to be available in the configured environment (see "Task module
requirements" above).

If the OpenVox/Puppet Server isn't set up or the task isn't available, you'll see a
`bolt/choria-task-download-failed` error. This is expected and tests that the
error path works correctly.

**run_task with parameters**

```bash
bolt task run package action=status name=puppet \
  --targets nodeA.example.com
```

Expected: Returns the package status. Verifies that task parameters are
passed through correctly to the bolt_tasks agent.

**run_command still fails (no shell agent)**

```bash
bolt command run 'whoami' --targets nodeA.example.com,nodeB.example.com
```

Expected: Still fails with the shell agent error. `bolt_tasks` doesn't help
with `run_command`.

**run_script still fails (no shell agent)**

```bash
bolt script run /tmp/test.sh --targets nodeA.example.com
```

Expected: Still fails with the shell agent error.

**Forced agent selection**

```bash
# Force bolt_tasks (should work, same as default)
bolt task run facts --targets nodeA.example.com --choria-task-agent bolt_tasks

# Force shell (should fail: not installed)
bolt task run facts --targets nodeA.example.com --choria-task-agent shell
```

Expected: First succeeds (or fails at download, not at agent detection).
Second fails with `bolt/choria-agent-not-available` for shell.

### Shell agent on one node (mixed fleet)

Install the shell agent on Node A only, leaving Node B with just
`bolt_tasks`. This tests mixed-fleet behavior.

**run_command (mixed results)**

```bash
bolt command run 'whoami' --targets nodeA.example.com,nodeB.example.com
```

Expected:
- Node A: Succeeds, shows username
- Node B: Fails with `bolt/choria-agent-not-available` (no shell agent)

This is the key mixed-fleet test. Both results should appear in the output,
not a single crash.

**run_command with exit code**

```bash
bolt command run 'exit 42' --targets nodeA.example.com
```

Expected: Reports exit code 42.

**run_script (mixed results)**

```bash
echo '#!/bin/bash
echo "hostname: $(hostname)"
echo "uptime: $(uptime)"' > /tmp/test_script.sh

bolt script run /tmp/test_script.sh --targets nodeA.example.com,nodeB.example.com
```

Expected: Same split. Node A succeeds, Node B fails.

**run_script with arguments**

```bash
echo '#!/bin/bash
echo "Args: $@"' > /tmp/test_args.sh

bolt script run /tmp/test_args.sh arg1 arg2 --targets nodeA.example.com
```

Expected: `Args: arg1 arg2`

**run_task (both succeed via bolt_tasks)**

```bash
bolt task run facts --targets nodeA.example.com,nodeB.example.com
```

Expected: Both succeed. Even though Node A has shell, bolt_tasks is the
default and both nodes have it.

**run_task with local task (not on OpenVox/Puppet Server)**

Test with a task that's NOT on the OpenVox/Puppet Server (a local custom task).
Without `--choria-task-agent shell`, this will fail because bolt_tasks can't find
the task on the OpenVox/Puppet Server:

```bash
mkdir -p tasks
cat > tasks/hello.sh << 'TASK'
#!/bin/bash
echo "{\"message\": \"hello from $(hostname)\"}"
TASK
cat > tasks/hello.json << 'META'
{"description": "Test task", "input_method": "stdin", "parameters": {}}
META

bolt task run choria_test::hello --targets nodeA.example.com
```

Expected: Fails with `bolt/choria-task-download-failed` and a message
suggesting `--choria-task-agent shell`.

Now retry with `--choria-task-agent shell` (Node A has the shell agent):

```bash
bolt task run choria_test::hello --targets nodeA.example.com --choria-task-agent shell
```

Expected: Succeeds via the shell agent.

**Agent selection**

```bash
# Use shell agent (Node A has it)
bolt task run choria_test::hello --targets nodeA.example.com --choria-task-agent shell

# Use shell agent (Node B doesn't have it)
bolt task run choria_test::hello --targets nodeB.example.com --choria-task-agent shell
```

Expected:
- First: Succeeds via shell agent
- Second: Fails with `bolt/choria-agent-not-available`

### Both agents installed

Install the shell agent on Node B too (same steps as above). Now both nodes
have both agents installed.

**All operations succeed on both nodes**

```bash
bolt command run 'whoami' --targets nodeA.example.com,nodeB.example.com
bolt script run /tmp/test_script.sh --targets nodeA.example.com,nodeB.example.com
bolt task run facts --targets nodeA.example.com,nodeB.example.com
bolt task run choria_test::hello --targets nodeA.example.com,nodeB.example.com --choria-task-agent shell
```

All should succeed on both nodes.

**upload/download still unsupported**

```bash
bolt file upload /tmp/test.sh /tmp/test_remote.sh --targets nodeA.example.com
bolt file download /etc/hostname /tmp/downloaded/ --targets nodeA.example.com
```

Still fails with `bolt/choria-unsupported-operation`, regardless of agents.

**Multiple targets**

```bash
bolt command run 'hostname -f' --targets nodeA.example.com,nodeB.example.com
```

Expected: Returns hostname from both nodes. Verifies multi-target fanout
works correctly.

**Timeouts**

Test that long-running commands are killed on timeout:

```bash
bolt command run 'sleep 300' --targets nodeA.example.com \
  --transport-config '{"choria": {"command-timeout": 5}}'
```

Expected: Times out after ~5 seconds, kills the background process on the
node (check debug logs for "Killed background process").

**Temp directory cleanup**

```bash
# With cleanup enabled (default)
bolt script run /tmp/test_script.sh --targets nodeA.example.com --log-level debug 2>&1 | \
  grep -i "tmpdir\|bolt-choria-"

# Verify nothing left behind
ssh nodeA.example.com 'ls /tmp/bolt-choria-* 2>/dev/null || echo "clean"'

# With cleanup disabled
bolt script run /tmp/test_script.sh --targets nodeA.example.com \
  --transport-config '{"choria": {"cleanup": false}}' --log-level debug

# Should still be there
ssh nodeA.example.com 'ls -la /tmp/bolt-choria-*'
# Clean up manually
ssh nodeA.example.com 'rm -rf /tmp/bolt-choria-*'
```

## Debug logging

Add `--log-level debug` to any OpenBolt command to see detailed transport traces:

- `Loaded Choria client config from ...` (config file found)
- `Discovering agents on N targets` (agent discovery start)
- `Discovered agents on <host>: ...` (per-target agent list)
- `The 'shell' agent on <host> is version X, but Y or later is required` (version check)
- `Running command via shell agent on N targets` (command start)
- `Running task <name> via bolt_tasks agent on N targets` (task routing)
- `Task <name> routing: agent: bolt_tasks, N capable / M incapable` (agent routing decision)
- `Started command on <host>, handle: ...` (shell agent start)
- `Poll round N: M targets still pending` (poll loop progress)
- `shell.list on <host>: handle ... status: stopped` (per-target poll result)
- `Fetching shell.statuses for N targets` (batched output fetch)
- `Uploading N bytes to <path> on M targets` (file upload)
- `Checking connectivity for N targets` (connectivity check)
- `Timed out after Ns with M targets still pending, killing processes` (timeout)
- `Killing timed-out processes on N targets` (kill start)

## Diagnostics

```bash
# Check what agents are available on a node (uses choria directly, not OpenBolt)
choria rpc rpcutil agent_inventory -I nodeA.example.com

# Check Choria connectivity
choria ping -I nodeA.example.com

# Enable debug logging in OpenBolt
bolt command run 'hostname' --targets nodeA.example.com --log-level debug
```

## Troubleshooting

**Timeouts on all operations:**
Check that target names in your inventory match the exact Choria identity
(FQDN) shown by `choria ping`. Mismatched names are the most common cause of
"no response" errors.

**DDL-not-found errors:**
The `bolt_tasks` DDL comes from the `choria-mcorpc-support` gem. If you see
DDL errors, verify the gem is installed (see "Install the choria-mcorpc-support
gem" above). The shell DDL is bundled with OpenBolt and does not need separate
installation.

**Task download 404 errors (`bolt/choria-task-download-failed`):**
The task module (and its dependencies like `ruby_task_helper`) must be
installed on the OpenVox/Puppet Server.

**Agent not found after install:**
Restart `choria-server` on the target node. The Go server only loads agents at
startup.

**MCollective refuses to run as root:**
Use a non-root user with a Puppet CA-signed certificate. See "Choria client
configuration" above.

**Agent cache shows stale data:**
OpenBolt caches agent lists per target for the transport's lifetime. Start a fresh
`bolt` command after installing or removing agents.

## Test matrix summary

| Operation    | No agents      | bolt_tasks only | shell only                | Both agents                          |
|-------------|----------------|-----------------|---------------------------|--------------------------------------|
| run_command | agent error    | agent error     | works                     | works (shell)                        |
| run_script  | agent error    | agent error     | works                     | works (shell)                        |
| run_task    | no-agent error | works (bt)      | works (--choria-task-agent sh) | works (bt default, sh if configured) |
| upload      | unsupported    | unsupported     | unsupported               | unsupported                          |
| download    | unsupported    | unsupported     | unsupported               | unsupported                          |
| connected?  | works          | works           | works                     | works                                |
