#compdef bolt
# ------------------------------------------------------------------------------
# Description
# -----------
#
#  Completion script for OpenBolt (https://github.com/OpenVoxProject/openbolt/).
#
# ------------------------------------------------------------------------------
# Authors
# -------
#
#  * OpenVox Project (https://github.com/OpenVoxProject/openbolt/)
#
# ------------------------------------------------------------------------------
#
# Install either by:
#   * sourcing this file in your ~/.zshrc, or
#   * copying this file into a directory in your $fpath as `_bolt` and
#     restarting the shell (the completion system must be initialized).
#
# Optional configuration (set in the shell before completing):
#   BOLT_COMPLETION_RUBY   ruby to use when jq is unavailable
#                          (default: /opt/puppetlabs/bolt/bin/ruby, bolt's
#                          bundled all-in-one interpreter; falls back to the
#                          system ruby if not found)
#   BOLT_COMPLETION_TARGETS  targets (not just groups) are offered for
#                          --targets/-t options; set to 0, "false", "off" or
#                          "no" to disable (useful for large inventories)
#
# Dynamic completions call `bolt plan show`, `bolt task show`, `bolt group
# show` and `bolt inventory show` (with `--format json`). Results are cached in memory
# for the shell session, keyed by project (the --project argument or the
# current directory) and the newest mtime among the project's definition
# files (bolt-project.yaml, inventory.yaml and first-level module
# directories), so entries refresh automatically when the project
# changes. Everything falls back to plain message completions when
# `bolt` is not on the PATH.

typeset -gA _bolt_cache

_bolt () {
  local curcontext="$curcontext" state line
  typeset -A opt_args
  integer ret=1

  # --- option groups --------------------------------------------------------
  # assembled to match lib/bolt/bolt_option_parser.rb
  local -a opts_globals=(
    '(- : *)'{-h,--help}'[Display help.]'
    '(- : *)'--version'[Display the version.]'
    '--log-level=[Set the log level for the console.]:level:(trace debug info warn error fatal)'
    '--clear-cache[Clear plugin, plan and task caches before executing.]'
  )

  local -a opts_inventory=(
    '(-q --query --rerun)'{-t=,--targets=}'[Targets of the command (comma separated names or URIs).]:targets: _bolt_target_list'
    '(-t --targets --rerun)'{-q=,--query=}'[Query PuppetDB to determine the targets.]:query: _message "PuppetDB query"'
    '(-t --targets -q --query)'--rerun='[Retry targets from the last run.]:filter:(all failure success)'
  )

  local -a opts_authentication=(
    '(-u --user)'{-u=,--user=}'[User to authenticate as.]:user:'
    '(-p --password)'{-p=,--password=}'[Password to authenticate with.]:password:'
    '--password-prompt[Prompt for user to input password.]'
    '--private-key=[Path to private ssh key to authenticate with.]:private key: _files'
    '(--no-host-key-check)--host-key-check[Check host keys with SSH.]'
    '(--host-key-check)--no-host-key-check[Do not check host keys with SSH.]'
    '(--no-ssl)--ssl[Use SSL with WinRM.]'
    '(--ssl)--no-ssl[Do not use SSL with WinRM.]'
    '(--no-ssl-verify)--ssl-verify[Verify remote host SSL certificate with WinRM.]'
    '(--ssl-verify)--no-ssl-verify[Do not verify remote host SSL certificate with WinRM.]'
  )

  local -a opts_escalation=(
    '--run-as=[User to run as using privilege escalation.]:run as user:'
    '--sudo-password=[Password for privilege escalation.]:sudo password:'
    '--sudo-password-prompt[Prompt for user to input escalation password.]'
    '--sudo-executable=[Specify an executable for running as another user.]:executable: _path_commands'
  )

  local -a opts_run_context=(
    '(-c --concurrency)'{-c=,--concurrency=}'[Maximum number of simultaneous connections.]:count: _guard "[0-9]#" number'
    '(-i --inventoryfile)'{-i=,--inventoryfile=}'[Inventory file to load.]:inventory file: _files'
    '(--no-save-rerun)--save-rerun[Update the rerun file after this command.]'
    '(--save-rerun)--no-save-rerun[Do not update the rerun file after this command.]'
    '(--no-cleanup)--cleanup[Clean up temporary files created on targets.]'
    '(--cleanup)--no-cleanup[Keep temporary files created on targets.]'
    '--puppetdb=[Named PuppetDB instance to connect to by default.]:instance:'
  )

  local -a opts_setters=(
    '(-m --modulepath)'{-m=,--modulepath=}'[List of directories containing modules (colon separated).]:modulepath: _files -/'
    '--project=[Path to load the Bolt project from.]:project: _files -/'
  )

  local -a opts_project=('--project=[Path to load the Bolt project from.]:project: _files -/')

  local -a opts_transports=(
    '--transport=[Specify a default transport.]:transport:(choria docker jail local lxd podman remote ssh winrm)'
    '--connect-timeout=[Connection timeout in seconds.]:seconds: _guard "[0-9]#" seconds'
    '(--no-native-ssh)--native-ssh[Shell out to native SSH instead of using net-ssh.]'
    '(--native-ssh)--no-native-ssh[Use the net-ssh Ruby library instead of native SSH.]'
    '--ssh-command=[Executable to use instead of the net-ssh Ruby library.]:command: _path_commands'
    '--copy-command=[Command to copy files to remote hosts with native SSH.]:command: _path_commands'
    '(--no-tty)--tty[Request a pseudo TTY on targets that support it.]'
    '(--tty)--no-tty[Do not request a pseudo TTY.]'
  )

  local -a opts_choria=(
    '--choria-config-file=[Path to a Choria/MCollective client configuration file.]:config file: _files'
    '--choria-mcollective-certname=[Override the MCollective certname for Choria client identity.]:certname:'
    '--choria-ssl-ca=[CA certificate path for Choria TLS authentication.]:ca file: _files'
    '--choria-ssl-cert=[Client certificate path for Choria TLS authentication.]:cert file: _files'
    '--choria-ssl-key=[Client private key path for Choria TLS authentication.]:key file: _files'
    '--choria-collective=[Choria collective to route messages through.]:collective:'
    '--choria-puppet-environment=[Puppet environment for choria file downloads (default: production).]:environment:'
    '--choria-rpc-timeout=[Seconds to wait for replies to individual Choria RPC calls.]:seconds: _guard "[0-9]#" seconds'
    '--choria-task-timeout=[Seconds to wait for task execution to complete.]:seconds: _guard "[0-9]#" seconds'
    '--choria-command-timeout=[Seconds to wait for commands and scripts to complete.]:seconds: _guard "[0-9]#" seconds'
    '--choria-brokers=[Choria broker addresses (comma separated host or host:port).]:brokers:'
    '--choria-broker-timeout=[Seconds to wait for the TCP connection to a Choria broker.]:seconds: _guard "[0-9]#" seconds'
  )

  local -a opts_display=(
    '--format=[Output format to use.]:format:(human json rainbow)'
    '(--no-color)--color[Show output in color.]'
    '(--color)--no-color[Do not show output in color.]'
    '(--no-verbose)'{-v,--verbose}'[Display verbose logging.]'
    '(--verbose -v)--no-verbose[Do not display verbose logging.]'
    '--trace[Display error stack traces.]'
    '--stream[Stream output from scripts and commands to the console.]'
  )

  # All "action" options: inventory + authentication + escalation +
  # run_context + global_config_setters + transports + choria + display
  local -a opts_action=(
    "${opts_inventory[@]}" "${opts_authentication[@]}" "${opts_escalation[@]}"
    "${opts_run_context[@]}" "${opts_setters[@]}" "${opts_transports[@]}"
    "${opts_choria[@]}" "${opts_display[@]}"
  )

  # --- shared tables (visible to the subcommand functions via dynamic scope)

  local -a _bolt_subcommands=(
    'apply:Apply Puppet manifest code'
    'command:Run a command remotely'
    'file:Copy files between the controller and targets'
    'group:Show the list of groups in the inventory'
    'guide:View guides for Bolt concepts and features'
    'inventory:Show the list of targets an action would run on'
    'lookup:Look up a value with Hiera'
    'module:Manage Bolt project modules'
    'plan:Convert, create, show and run Bolt plans'
    'plugin:Show available plugins'
    'policy:Apply, create and show policies'
    'project:Create and migrate Bolt projects'
    'script:Upload a local script and run it remotely'
    'secret:Create encryption keys and encrypt and decrypt values'
    'task:Show and run Bolt tasks'
  )

  local -a _bolt_guide_topics=(
    'debugging:Debug when Bolt is not behaving as expected'
    'inventory:Define and configure targets'
    'links:Find OpenBolt documentation'
    'logging:Configure logs and logging'
    'module:Install and manage modules'
    'modulepath:Understand the modulepath and module directories'
    'project:Create projects to add configuration and data'
    'targets:Target devices with the Bolt targets syntax'
    'transports:Configure connections with transports'
  )

  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0

  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t subcommands 'subcommand' _bolt_subcommands
    else
      compset -n 1
      case $line[1] in
        apply)     _bolt_apply ;;
        command)   _bolt_command ;;
        file)      _bolt_file ;;
        group)     _bolt_group ;;
        guide)     _bolt_guide ;;
        help)      _bolt_help ;;
        inventory) _bolt_inventory ;;
        lookup)    _bolt_lookup ;;
        module)    _bolt_module ;;
        plan)      _bolt_plan ;;
        plugin)    _bolt_plugin ;;
        policy)    _bolt_policy ;;
        project)   _bolt_project ;;
        script)    _bolt_script ;;
        secret)    _bolt_secret ;;
        task)      _bolt_task ;;
        *)         _message "unknown subcommand: $line[1]" ;;
      esac
    fi
  fi

  return ret
}

# --- dynamic helpers ---------------------------------------------------------

# Prints a change-sentinel for the effective project: the newest mtime
# among bolt-project.yaml, inventory.yaml and the first-level module
# directories, or an empty string when none of them exist (entries are
# then valid for the shell session only).
_bolt_project_stamp () {
  local proj="${(Q)${opt_args[--project]:-}}"
  [[ -z $proj ]] && proj="$PWD"
  local stamp m f
  zmodload -F zsh/stat b:zstat 2>/dev/null
  for f in "$proj/bolt-project.yaml" "$proj/inventory.yaml" "$proj/modules"/*(/N) "$proj/bolt-modules"/*(/N); do
    [[ -e $f ]] || continue
    m=$( zstat +mtime "$f" 2>/dev/null ) || continue
    (( $m > ${stamp:-0} )) && stamp=$m
  done
  if [[ -n $stamp ]]; then
    print -r -- "$stamp"
  fi
}

# Applies JQEXPR (or equivalent RUBYSNIP) to JSON read from stdin; prints
# one result per line. Uses jq when available, else ruby — preferring
# bolt's bundled interpreter (all-in-one package, see BOLT_COMPLETION_RUBY)
# over the system ruby.
_bolt_json_parse () {
  local jqexpr="$1" rubysnip="$2"
  if (( $+commands[jq] )); then
    jq -r "$jqexpr" 2>/dev/null
    return
  fi
  local -a ruby
  ruby=( "${BOLT_COMPLETION_RUBY:-/opt/puppetlabs/bolt/bin/ruby}" )
  [[ -x $ruby[1] ]] || ruby=( ruby )
  "${ruby[@]}" -rjson -e "$rubysnip" 2>/dev/null
}

# Returns a filesystem-safe key identifying the effective project
# (--project argument, or the current directory).
_bolt_project_key () {
  local proj="${(Q)${opt_args[--project]:-}}"
  [[ -z $proj ]] && proj="$PWD"
  print -r -- "${proj//[^a-zA-Z0-9]/_}"
}

# Fetches the NAMES for KIND ('plans', 'tasks' or 'groups') via
# `bolt plan/task/group show --format json`, using the per-project
# in-memory cache. Sets reply and returns 0 on success. Must not be
# called within a subshell, or the cache would not survive.
_bolt_fetch_list () {
  local kind="$1" key appcmd jsonkey jqexpr rubysnip
  key="${kind}:$( _bolt_project_key ):$( _bolt_project_stamp )"
  if [[ -n ${_bolt_cache[$key]:-} ]]; then
    reply=( ${(f)_bolt_cache[$key]} )
    return 0
  fi

  # map the kind to a bolt subcommand and its JSON list key
  case $kind in
    plans)   appcmd=( plan )      jsonkey=plans ;;
    tasks)   appcmd=( task )      jsonkey=tasks ;;
    groups)  appcmd=( group )     jsonkey=groups ;;
    targets) appcmd=( inventory ) jsonkey=targets ;;
  esac

  cmd_opts=()
  if [[ -n ${(Q)${opt_args[--project]:-}} ]]; then
    cmd_opts=( --project "${(Q)${opt_args[--project]}}" )
  fi
  if (( $+commands[bolt] )); then
    local json
    json=$( bolt "$appcmd" show "${cmd_opts[@]}" --format json 2>/dev/null )
    if [[ -n $json ]]; then
      local -a names
      # plan/task lists are [["name","description"],...] pairs, the rest are plain name strings
      if [[ $kind == plans || $kind == tasks ]]; then
        jqexpr=".${jsonkey}[] | .[0]"
        rubysnip="begin; JSON.parse(STDIN.read)['$jsonkey'].each { |e| puts e[0] }; rescue; end"
      else
        jqexpr=".${jsonkey}[]"
        rubysnip="begin; JSON.parse(STDIN.read)['$jsonkey'].each { |e| puts e }; rescue; end"
      fi
      names=( ${(f)"$( printf '%s' "$json" | _bolt_json_parse "$jqexpr" "$rubysnip" )"} )
      names=( ${(u)names} )
      if (( #names )); then
        _bolt_cache[$key]="${(F)names}"
        reply=( "${names[@]}" )
        return 0
      fi
    fi
  fi
  reply=()
  return 1
}

# Completes plan names from `bolt plan show`.
#
# NOTE: uses _alternative instead of _describe, because plan names contain
# '::' which _describe renders as a "name:desc" separator (e.g. it displayed
# `aggregate -- :count` instead of `aggregate::count`).
_bolt_plan_names () {
  if _bolt_fetch_list plans; then
    _alternative "plans:plan:( $reply )"
  else
    _message "plan name"
  fi
}

# Completes task names from `bolt task show`.
_bolt_task_names () {
  if _bolt_fetch_list tasks; then
    _alternative "tasks:task:( $reply )"
  else
    _message "task name"
  fi
}

# Completes plan parameters as "name=" via `bolt plan show <plan>`.
_bolt_plan_params () {
  local plan
  compset -P '*=*' && { _message "parameter value"; return }
  if [[ -n ${opt_args[--params]} ]]; then
    _message "parameter (parameters were already given with --params)"; return
  fi
  plan="${line[1]:-}"
  if [[ -z $plan ]]; then
    plan="${words[1]:-}"
  fi
  local -a names opts
  opts=()
  if [[ -n ${(Q)${opt_args[--project]:-}} ]]; then
    opts=( --project "${(Q)${opt_args[--project]}}" )
  fi
  if [[ -n $plan ]] && (( $+commands[bolt] )); then
    local json
    json=$( bolt plan show "$plan" "${opts[@]}" --format json 2>/dev/null )
    if [[ -n $json ]]; then
      names=( ${(f)"$( printf '%s' "$json" | _bolt_json_parse '.parameters // {} | keys | .[]' 'begin; JSON.parse(STDIN.read)["parameters"].each_key { |k| puts k }; rescue; end' )"} )
    fi
  fi
  names=( ${(u)names/%/=} )
  if (( #names )); then
    _describe -t parameters 'plan parameter' names
  else
    _message "parameter=value"
  fi
}

# Completes task parameters as "name=" via `bolt task show <task>`.
_bolt_task_params () {
  local task
  compset -P '*=*' && { _message "parameter value"; return }
  if [[ -n ${opt_args[--params]} ]]; then
    _message "parameter (parameters were already given with --params)"; return
  fi
  task="${line[1]:-}"
  if [[ -z $task ]]; then
    task="${words[1]:-}"
  fi
  local -a names opts
  opts=()
  if [[ -n ${(Q)${opt_args[--project]:-}} ]]; then
    opts=( --project "${(Q)${opt_args[--project]}}" )
  fi
  if [[ -n $task ]] && (( $+commands[bolt] )); then
    local json
    json=$( bolt task show "$task" "${opts[@]}" --format json 2>/dev/null )
    if [[ -n $json ]]; then
      names=( ${(f)"$( printf '%s' "$json" | _bolt_json_parse '.metadata.parameters // {} | (if type == "object" then keys[] else empty end)' 'begin; ps = JSON.parse(STDIN.read)["metadata"]["parameters"]; ps.is_a?(Hash) and ps.each_key { |k| puts k }; rescue; end' )"} )
      names=( ${(u)names/%/=} )
    fi
  fi
  if (( #names )); then
    _describe -t parameters 'task parameter' names
  else
    _message "parameter=value"
  fi
}

# Completes target names (comma separated list); cached in memory.
# Offers groups from `bolt group show`, plus individual targets from
# `bolt inventory show` unless BOLT_COMPLETION_TARGETS disables the latter.
_bolt_target_list () {
  local -a tnames
  if _bolt_fetch_list groups; then
    tnames=( "$reply[@]" )
  fi
  if [[ ${BOLT_COMPLETION_TARGETS:-1} != (0|false|off|no) ]] && _bolt_fetch_list targets; then
    tnames+=( "$reply[@]" )
  fi
  tnames=( ${(u)tnames} )
  if (( #tnames )); then
    _values -s , 'target' "$tnames[@]"
  else
    _message "comma separated target list"
  fi
}

# --- subcommands -------------------------------------------------------------

_bolt_apply () {
  _arguments \
    '(-e --execute)'{-e=,--execute=}'[Puppet manifest code to apply to the targets.]:manifest code:' \
    '--noop[See what changes Bolt will make without executing them.]' \
    '--compile-concurrency=[Maximum number of simultaneous manifest block compiles.]:count: _guard "[0-9]#" number' \
    '--hiera-config=[Specify where to load Hiera config from.]:hiera config: _files' \
    "${opts_action[@]}" \
    ':manifest file: _files'
}

_bolt_guide () {
  local -a topics
  topics=( "${_bolt_guide_topics[@]}" )
  _arguments \
    '--format=[Output format to use.]:format:(human json rainbow)' \
    "${opts_globals[@]}" \
    ':topic: _describe "guide" topics'
}

_bolt_lookup () {
  _arguments \
    '(-t --targets -q --query)'--plan-hierarchy'[Look up the value with Hiera in the context of a plan.]' \
    '--hiera-config=[Specify where to load Hiera config from.]:hiera config: _files' \
    "${opts_action[@]}" \
    ':Hiera key: _message "key to look up"'
}

_bolt_command () {
  integer ret=1
  local -a actions
  actions=('run:Run a command on the specified targets')
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        run) _bolt_command_run ;;
        *)   _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_command_run () {
  _arguments \
    '--env-var=[Environment variables to set on the target.]:environment variable: _message "name=value"' \
    "${opts_action[@]}" \
    ':remote command: _message "command to run"'
}

_bolt_file () {
  integer ret=1
  local -a actions
  actions=(
    'download:Download a file or directory to the controller'
    'upload:Upload a local file or directory from the controller'
  )
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        download) _bolt_file_download ;;
        upload)   _bolt_file_upload ;;
        *)        _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_file_download () {
  _arguments \
    "${opts_action[@]}" \
    ':remote source: _message "remote file"' \
    ':destination directory: _files -/'
}

_bolt_file_upload () {
  _arguments \
    '--tmpdir=[Directory to upload and execute temporary files on the target.]:tmpdir: _files -/' \
    "${opts_action[@]}" \
    ':source file or directory: _files' \
    ':remote destination: _message "remote path"'
}

_bolt_group () {
  integer ret=1
  local -a actions
  actions=('show:Show the list of groups in the inventory')
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        show) _bolt_group_show ;;
        *)    _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_group_show () {
  _arguments \
    "${opts_globals[@]}" "${opts_project[@]}" "${opts_display[@]}" \
    '--inventoryfile=[Specify where to load inventory from.]:inventory file: _files'
}

_bolt_inventory () {
  integer ret=1
  local -a actions
  actions=('show:Show the list of targets an action would run on')
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        show) _bolt_inventory_show ;;
        *)    _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_inventory_show () {
  _arguments \
    "${opts_inventory[@]}" "${opts_globals[@]}" "${opts_project[@]}" "${opts_display[@]}" \
    '--inventoryfile=[Specify where to load inventory from.]:inventory file: _files' \
    '--detail[Show resolved configuration for the targets.]'
}

_bolt_module () {
  integer ret=1
  local -a actions
  actions=(
    'add:Add a module to the project'
    'generate-types:Generate type references to register in plans'
    'install:Install the modules of the project'
    'show:List modules available to the Bolt project'
  )
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        add)            _bolt_module_add ;;
        generate-types) _bolt_module_generate_types ;;
        install)        _bolt_module_install ;;
        show)           _bolt_module_show ;;
        *)              _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_module_add () {
  _arguments \
    "${opts_globals[@]}" "${opts_project[@]}" \
    ':module: _message "module name (e.g. puppetlabs-apt)"'
}

_bolt_module_generate_types () {
  _arguments \
    "${opts_globals[@]}" "${opts_setters[@]}"
}

_bolt_module_install () {
  _arguments \
    "${opts_globals[@]}" "${opts_project[@]}" \
    '(--no-resolve)--resolve[Resolve modules configured in bolt-project.yaml.]' \
    '(--resolve)--no-resolve[Install modules from the Puppetfile without resolving configured modules.]' \
    '--force[Force a destructive action.]'
}

_bolt_module_show () {
  _arguments \
    "${opts_globals[@]}" "${opts_setters[@]}" \
    '::module: _message "module name"'
}

_bolt_plan () {
  integer ret=1
  local -a actions
  actions=(
    'convert:Convert a YAML plan to a Bolt plan'
    'new:Create a new plan in the current project'
    'run:Run a plan on the specified targets'
    'show:Show available plans and plan documentation'
  )
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        convert) _bolt_plan_convert ;;
        new)     _bolt_plan_new ;;
        run)     _bolt_plan_run ;;
        show)    _bolt_plan_show ;;
        *)       _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_plan_convert () {
  _arguments \
    "${opts_globals[@]}" "${opts_setters[@]}" \
    ':plan: _bolt_plan_names'
}

_bolt_plan_new () {
  _arguments \
    "${opts_globals[@]}" "${opts_project[@]}" \
    '--pp[Create a new Puppet language plan.]' \
    ':plan name: _message "plan name (mymodule::myplan)"'
}

_bolt_plan_run () {
  _arguments \
    '--params=[Parameters to a plan as JSON, a JSON file, or stdin.]:params: _message "JSON parameters"' \
    '--compile-concurrency=[Maximum number of simultaneous manifest block compiles.]:count: _guard "[0-9]#" number' \
    '--tmpdir=[Directory to upload and execute temporary files on the target.]:tmpdir: _files -/' \
    '--hiera-config=[Specify where to load Hiera config from.]:hiera config: _files' \
    "${opts_action[@]}" \
    ':plan: _bolt_plan_names' \
    '*::plan parameter: _bolt_plan_params'
}

_bolt_plan_show () {
  _arguments \
    "${opts_globals[@]}" "${opts_setters[@]}" \
    '--filter=[Filter plans by a matching substring.]:filter: _message "substring filter"' \
    '--format=[Output format to use.]:format:(human json rainbow)' \
    '::plan: _bolt_plan_names'
}

_bolt_plugin () {
  integer ret=1
  local -a actions
  actions=('show:Show available plugins')
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        show) _bolt_plugin_show ;;
        *)    _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_plugin_show () {
  _arguments \
    "${opts_globals[@]}" "${opts_setters[@]}" \
    '--format=[Output format to use.]:format:(human json rainbow)'
}

_bolt_policy () {
  integer ret=1
  local -a actions
  actions=(
    'apply:Apply a policy to the specified targets'
    'new:Create a new policy in the current project'
    'show:Show available policies'
  )
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        apply) _bolt_policy_apply ;;
        new)   _bolt_policy_new ;;
        show)  _bolt_policy_show ;;
        *)     _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_policy_apply () {
  _arguments \
    '--compile-concurrency=[Maximum number of simultaneous manifest block compiles.]:count: _guard "[0-9]#" number' \
    '--hiera-config=[Specify where to load Hiera config from.]:hiera config: _files' \
    '--noop[See what changes Bolt will make without executing them.]' \
    "${opts_action[@]}" \
    ':policy: _message "policy (comma separated list to apply several)"'
}

_bolt_policy_new () {
  _arguments \
    "${opts_globals[@]}" "${opts_project[@]}" \
    ':policy name: _message "policy name"'
}

_bolt_policy_show () {
  _arguments \
    "${opts_globals[@]}" "${opts_project[@]}"
}

_bolt_project () {
  integer ret=1
  local -a actions
  actions=(
    'init:Create a new Bolt project'
    'migrate:Migrate a Bolt project to the latest version'
  )
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        init)    _bolt_project_init ;;
        migrate) _bolt_project_migrate ;;
        *)       _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_project_init () {
  _arguments \
    "${opts_globals[@]}" \
    '--modules=[Modules to install from the Puppet Forge (comma separated).]:modules: _message "comma separated module names"' \
    '::project name: _message "project name"'
}

_bolt_project_migrate () {
  _arguments \
    "${opts_globals[@]}" "${opts_project[@]}" \
    '--inventoryfile=[Specify where to load inventory from.]:inventory file: _files'
}

_bolt_script () {
  integer ret=1
  local -a actions
  actions=('run:Run a script on the specified targets')
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        run) _bolt_script_run ;;
        *)   _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_script_run () {
  _arguments \
    '--tmpdir=[Directory to upload and execute temporary files on the target.]:tmpdir: _files -/' \
    '--env-var=[Environment variables to set on the target.]:environment variable: _message "name=value"' \
    "${opts_action[@]}" \
    ':script: _files' \
    '*::script argument: _message "script argument"'
}

_bolt_secret () {
  integer ret=1
  local -a actions
  actions=(
    'createkeys:Create new encryption keys'
    'decrypt:Decrypt a value'
    'encrypt:Encrypt a value'
  )
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        createkeys) _bolt_secret_createkeys ;;
        decrypt)    _bolt_secret_decrypt ;;
        encrypt)    _bolt_secret_encrypt ;;
        *)          _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_secret_createkeys () {
  _arguments \
    "${opts_globals[@]}" "${opts_setters[@]}" \
    '--plugin=[Select the plugin to use.]:plugin: _message "plugin name"' \
    '--force[Force a destructive action.]'
}

_bolt_secret_decrypt () {
  _arguments \
    "${opts_globals[@]}" "${opts_setters[@]}" \
    '--plugin=[Select the plugin to use.]:plugin: _message "plugin name"' \
    ':ciphertext: _message "ciphertext"'
}

_bolt_secret_encrypt () {
  _arguments \
    "${opts_globals[@]}" "${opts_setters[@]}" \
    '--plugin=[Select the plugin to use.]:plugin: _message "plugin name"' \
    '::plaintext: _message "plaintext"'
}

_bolt_task () {
  integer ret=1
  local -a actions
  actions=(
    'run:Run a Bolt task'
    'show:Show available tasks and task documentation'
  )
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t actions 'action' actions
    else
      compset -n 1
      case $line[1] in
        run)  _bolt_task_run ;;
        show) _bolt_task_show ;;
        *)    _message "unknown action: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_task_run () {
  _arguments \
    '--params=[Parameters to a task as JSON, a JSON file, or stdin.]:params: _message "JSON parameters"' \
    '--tmpdir=[Directory to upload and execute temporary files on the target.]:tmpdir: _files -/' \
    '--noop[See what changes Bolt will make without executing them.]' \
    '--choria-task-agent=[Which Choria agent to use for task execution.]:agent:(bolt_tasks shell)' \
    "${opts_action[@]}" \
    ':task: _bolt_task_names' \
    '*::task parameter: _bolt_task_params'
}

_bolt_task_show () {
  _arguments \
    "${opts_globals[@]}" "${opts_setters[@]}" \
    '--filter=[Filter tasks by a matching substring.]:filter: _message "substring filter"' \
    '--format=[Output format to use.]:format:(human json rainbow)' \
    '::task: _bolt_task_names'
}

# --- bolt help ---------------------------------------------------------------

_bolt_help () {
  integer ret=1
  _arguments -C \
    "${opts_globals[@]}" \
    '*::: :->args' && ret=0
  if [[ -n $state ]]; then
    if (( CURRENT == 1 )); then
      _describe -t subcommands 'subcommand' _bolt_subcommands
    else
      compset -n 1
      case ${line[1]} in
        command)   _bolt_help_action run ;;
        file)      _bolt_help_action 'download upload' ;;
        group)     _bolt_help_action show ;;
        guide)     _nothing ;;
        inventory) _bolt_help_action show ;;
        lookup)    _nothing ;;
        module)    _bolt_help_action 'add generate-types install show' ;;
        plan)      _bolt_help_action 'convert new run show' ;;
        plugin)    _bolt_help_action show ;;
        policy)    _bolt_help_action 'apply new show' ;;
        project)   _bolt_help_action 'init migrate' ;;
        script)    _bolt_help_action run ;;
        secret)    _bolt_help_action 'createkeys encrypt decrypt' ;;
        task)      _bolt_help_action 'run show' ;;
        *)         _message "unknown subcommand: $line[1]" ;;
      esac
    fi
  fi
  return ret
}

_bolt_help_action () {
  local -a actions
  actions=( ${=${1}} )
  if (( CURRENT == 2 )); then
    _describe -t actions 'action' actions
  fi
}

if [ "$funcstack[1]" = "_bolt" ]; then
  _bolt "$@"
else
  compdef _bolt bolt
fi

# Local Variables:
# mode: Shell-Script
# sh-indentation: 2
# indent-tabs-mode: nil
# sh-basic-offset: 2
# End:
# vim: ft=zsh sw=2 ts=2 et
