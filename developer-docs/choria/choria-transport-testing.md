# Choria Transport: Test Environment Setup

A guide for setting up a Choria test environment alongside an existing OpenVox
Puppet installation, and verifying all Choria transport functionality in OpenBolt.

For configuration reference, see the
[Choria transport user guide](https://docs.openvoxproject.org/openbolt/latest/choria-transport.html).
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

### Client certificate

The user running OpenBolt needs a certificate signed by the Puppet CA.
There are two approaches:

**Option A: Generate a `.mcollective` certificate (traditional)**

For non-root users, MCollective resolves the certname as
`<username>.mcollective` by default. Generate a matching certificate on
the primary server:

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

**Option B: Reuse the host's Puppet certificate**

If the non-root user can read the host's Puppet SSL files (e.g. via
group membership in the `puppet` group), you can skip certificate
generation and use the host's own cert with `--choria-mcollective-certname`
to override the automatic `<username>.mcollective` certname:

```bash
bolt task run facts --targets node1.example.com \
  --transport choria \
  --choria-ssl-cert /etc/puppetlabs/puppet/ssl/certs/$(hostname -f).pem \
  --choria-ssl-key /etc/puppetlabs/puppet/ssl/private_keys/$(hostname -f).pem \
  --choria-ssl-ca /etc/puppetlabs/puppet/ssl/certs/ca.pem \
  --choria-mcollective-certname $(hostname -f)
```

This requires a permissive `certname_whitelist` on the Choria servers
(e.g. `/.*/`) since the host's FQDN does not match the default
`\.mcollective$` pattern. In production, use a more restrictive pattern
such as `/.*\.example\.com$/` to limit which certnames are accepted. See
[Non-root certname](https://docs.openvoxproject.org/openbolt/latest/choria-transport.html#non-root-certname)
in the user guide for details.

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
plugin.choria.middleware_hosts = primary.example.com:4222
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
[Target names must match Choria identities](https://docs.openvoxproject.org/openbolt/latest/choria-transport.html#target-names-must-match-choria-identities)
in the user guide for details and workarounds using `name` with `host` config.

## Setting up Choria infrastructure via Puppet

The `choria` Puppet module manages the Choria server, broker, and MCO Ruby
compatibility layer on your nodes. The `bolt_tasks` and `shell` agents are
Ruby MCollective agents that run through Choria's MCO compatibility shim. The
`file_transfer` agent is a Choria external agent, a Ruby script the server
runs directly with Puppet's Ruby.

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
mod 'mcollective_agent_file_transfer',
  git: 'https://github.com/overlookinfra/file_transfer-agent',
  ref: 'main'
```

The shell agent requires version 1.2.1 or later (for the batched `statuses`
action). The file_transfer agent requires version 1.0.0 or later, and its
module also has to be applied on the OpenBolt controller with
`client => true`, since it carries the client library the transport uses.
The `bolt_tasks` agent is included in a standard Choria install and does not
need a separate Puppetfile entry.

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

# Allow all callers for testing. In production, restrict callers to specific
# certnames or a domain pattern like /.*\.example\.com$/.
mcollective::site_policies:
  - action: "allow"
    callers: "/.*/"
    actions: "*"
    facts: "*"
    classes: "*"

mcollective::client: true
# Allow all certnames for testing. In production, replace /.*/ with a pattern
# matching your environment, such as /.*\.example\.com$/.
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
  - mcollective_agent_file_transfer
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

The agent list includes `bolt_tasks`, `shell`, and `file_transfer`. The
file_transfer entry carries `provider: external`.

**Client-side DDLs and the file_transfer client library:** The `bolt_tasks`
DDL comes from the `choria-mcorpc-support` gem and the `shell` DDL is
bundled with OpenBolt. The `file_transfer` DDL and the client library the
transport uses come from the agent module: apply
`mcollective_agent_file_transfer` with `client => true` on the OpenBolt
controller, which installs them under the Choria libdir. Without them
`upload`, `download`, and large shell-path tasks fail with
`bolt/choria-file-transfer-library` naming the module.

**Policies:** the module writes `policies/file_transfer.policy` from the site
policies above. A read-only grant lists only `stat list get` in `actions`.
Per-path restrictions need the rego authorization provider and the
`mcollective_agent_file_transfer::rego_policy_source` parameter. Without any
policy file the Choria server denies every request to the agent.

### Removing agents for testing

To test downgrade scenarios (verifying error messages when agents are missing),
remove agents from `mcollective::plugin_classes` in Hiera and set absent:

```yaml
mcollective_agent_shell::ensure: absent
mcollective_agent_file_transfer::ensure: absent
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

**upload/download (needs file_transfer agent)**

```bash
bolt file upload /tmp/test.sh /tmp/test_remote.sh --targets nodeA.example.com
bolt file download /etc/hostname /tmp/downloaded/ --targets nodeA.example.com
```

Expected: Both fail with `bolt/choria-agent-not-available` naming the
`file_transfer` agent, before anything is sent.

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

**upload/download still need the file_transfer agent**

```bash
bolt file upload /tmp/test.sh /tmp/test_remote.sh --targets nodeA.example.com
```

Still fails with `bolt/choria-agent-not-available` until the file_transfer
agent is installed, see the file_transfer section below.

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

### file_transfer agent installed

Install the file_transfer agent on both nodes through
`mcollective::plugin_classes` as above, and its client files on the
controller with `client => true`. The transport needs it for `upload` and
`download`. Transfers through Choria are meant for smaller files.
Every chunk is a signed RPC round trip, so gigabytes belong on a file server.

**Upload a file**

```bash
head -c 3000000 /dev/urandom > /tmp/three_mb.bin
bolt file upload /tmp/three_mb.bin /tmp/uploaded.bin --targets nodeA.example.com,nodeB.example.com --log-level debug 2>&1 | \
  grep -i "bytes of data\|Uploaded"
ssh nodeA.example.com 'sha256sum /tmp/uploaded.bin; stat -c %a /tmp/uploaded.bin'
sha256sum /tmp/three_mb.bin
```

Expected: the debug log names the bytes each message carries, both nodes report success,
the digests match, and the mode matches the source. No
`.file_transfer-` file is left beside the destination on either node.

**Upload into an existing directory**

```bash
bolt file upload /tmp/three_mb.bin /var/tmp --targets nodeA.example.com
ssh nodeA.example.com 'ls -l /var/tmp/three_mb.bin'
```

Expected: the file lands inside the directory under its own name, as `mv`
would place it.

**Upload a directory**

```bash
mkdir -p /tmp/tree/sub && echo top > /tmp/tree/top.txt && echo inner > /tmp/tree/sub/inner.txt && chmod 750 /tmp/tree/sub
bolt file upload /tmp/tree /tmp/tree_remote --targets nodeA.example.com
ssh nodeA.example.com 'find /tmp/tree_remote -printf "%m %p\n"'
```

Expected: both files and both directories arrive with their modes.

**Upload a directory holding symbolic links**

```bash
mkdir -p /tmp/tree2/releases/one && echo app > /tmp/tree2/releases/one/app.rb
ln -s /tmp/tree2/releases/one /tmp/tree2/current
ln -s /tmp/tree2/releases/one/app.rb /tmp/tree2/app_link.rb
bolt file upload /tmp/tree2 /tmp/tree2_remote --targets nodeA.example.com
ssh nodeA.example.com 'find /tmp/tree2_remote -type f'
```

Expected: `releases/one/app.rb` and `app_link.rb` arrive as regular files,
and `current` is skipped with a warning naming it as a link to a directory.

**Download a file from several targets**

```bash
bolt file download /var/log/messages /tmp/downloaded --targets nodeA.example.com,nodeB.example.com
ls -l /tmp/downloaded/*/messages
```

Expected: one copy per target under `/tmp/downloaded/<target>/`, each
matching `sha256sum` on its node.

**Download a directory**

```bash
bolt file download /etc/choria /tmp/downloaded --targets nodeA.example.com
```

Expected: the tree arrives under `/tmp/downloaded/<target>/choria/`. A
symbolic link to a directory inside the tree is skipped with a warning.

**Download a directory that differs between targets**

```bash
ssh nodeA.example.com 'mkdir -p /tmp/mixed && echo a > /tmp/mixed/a.txt && echo b > /tmp/mixed/b.txt'
ssh nodeB.example.com 'mkdir -p /tmp/mixed && echo b > /tmp/mixed/b.txt'
bolt file download /tmp/mixed /tmp/downloaded --targets nodeA.example.com,nodeB.example.com
find /tmp/downloaded -type f
```

Expected: both targets succeed. nodeA delivers both files and nodeB delivers
`b.txt` alone. A file only one target holds is fetched only from that
target, with the size, digest and mode its listing carried, so the other
is not failed for not having it.

**A short timeout**

```bash
mco file_transfer upload /tmp/three_mb.bin /tmp/short_timeout.bin \
  -I nodeA.example.com -I unreachable.example.com --rpc-timeout 5
```

Expected: nodeA reports its landing path, the unreachable identity reports
no response to the stat call about two minutes after the command starts,
since the wait is never shorter than the agent's DDL timeout of 120
seconds, and the exit code is 2. The identity filter skips discovery, so
the library's own calls are what wait. The command's `--rpc-timeout` is
the library's wait, and mco's own `--timeout` has no effect on this command, since
the gem replaces a client timeout of exactly 5 with the agent's DDL
timeout plus the discovery timeout, and the library sets its own timeout
after building the client to keep the value given. A target OpenBolt cannot
reach fails during agent discovery with `bolt/choria-agent-not-available`
before the library runs, so the bolt command cannot show this case.

**Checksum change during a download**

Start a download of a large file and overwrite bytes inside it on the node
while the transfer runs. An append would not do, since the download reads
only up to the size the stat reported:

```bash
ssh nodeA.example.com 'head -c 200000000 /dev/urandom > /tmp/big.bin'
bolt file download /tmp/big.bin /tmp/downloaded --targets nodeA.example.com &
ssh nodeA.example.com 'printf changed | dd of=/tmp/big.bin bs=1 seek=190000000 conv=notrunc'
wait
```

Expected: the target fails with `bolt/choria-checksum-mismatch` naming both
digests, and nothing is left under `/tmp/downloaded/<target>/`.

**Upload to a missing directory**

Upload a file to a destination whose parent directory does not exist on
the node. Expected: the target fails at the first chunk with
`Errno::ENOENT` naming the directory, and nothing is left on the node.

**Interrupted upload**

Interrupt an upload of a large file with Ctrl-C. Expected under OpenBolt,
whose Ctrl-C handler exits at once: `.file_transfer-<token>` beside the
destination on each target, to remove by hand. Expected under
`mco file_transfer`, which finishes the call it is in: the library's
`abort` removes the file where it reaches the node.

**Policy denial**

Replace the site policy allow line with one that grants only `stat list get`
to the OpenBolt certname and run an upload. Expected: every target fails at
the first `put` with an authorization error from the Choria server, and nothing is
written. A download still works.

**Payload limit warnings**

Lower `message-data-size`, which is in kibibytes, below the minimum and above it:

```bash
bolt file upload /tmp/three_mb.bin /tmp/uploaded.bin --targets nodeA.example.com \
  --transport-config '{"choria": {"message-data-size": 64}}' --log-level debug 2>&1 | grep "bytes of data"
```

Expected: `Each message carries up to 65536 bytes of data`. Without the
option the line names 524288, half the Choria broker's 1 MiB limit.
A `message-data-size` below 1 is refused by config validation. A request
the broker's limit refuses fails its targets with
`bolt/choria-payload-too-large` and a message naming a lower
`message-data-size` as the remedy.

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
- `The shell.list call on <host> reports handle ... as stopped` (per-target poll result)
- `Fetching shell.statuses for N targets` (batched output fetch)
- `Uploading N bytes to <path> on M targets` (inline shell upload of a task file)
- `Each message carries up to B bytes of data` (message sizing, 512 KiB unless set)
- `Upload of <source> to <destination> on N nodes` (file_transfer upload start)
- `Upload chunks go to N nodes per request` (the file_transfer upload batch size)
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
| upload      | agent error    | agent error     | agent error               | agent error (needs file_transfer)    |
| download    | agent error    | agent error     | agent error               | agent error (needs file_transfer)    |
| connected?  | works          | works           | works                     | works                                |

With the file_transfer agent installed as well, `upload` and `download` work
on every target that has it. The two agents do not depend on each other.
