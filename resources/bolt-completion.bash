#####################################################################
###
### Bash autocompletion for bolt
### include this file in your .bash_profile or .bashrc to use completion
### "source bolt-completion.bash"
###
### Marc Schoechlin ms-github@256bit.org
###
### OpenVox additions: plan/task names, plan/task parameters, targets
### (groups and individual targets) and guide topics are completed via the
### CLI (live `bolt` calls; cached in memory per shell session and project),
### matching the zsh completion in resources/bolt-completion.zsh.
### Requires bash >= 4 (associative arrays).
###
### Optional configuration (set in the shell before completing):
###   BOLT_COMPLETION_TARGETS  individual targets are offered for
###                            --targets/-t, not just groups; set to 0,
###                            "false", "off" or "no" to disable (useful
###                            for large inventories)
###   BOLT_COMPLETION_RUBY     ruby to use when jq is unavailable
###                            (default: /opt/puppetlabs/bolt/bin/ruby, bolt's
###                            bundled all-in-one interpreter; falls back to
###                            the system ruby if not found)
###
#####################################################################

if (( BASH_VERSINFO[0] < 4 )); then
  echo "bolt-completion.bash requires bash >= 4" >&2
  return 1 2>/dev/null || exit 1
fi

# Per-shell-session completion cache: newline-joined name lists per
# "<kind>|<project key>|<project stamp>" key; the stamp is the newest mtime
# among the project files, so entries refresh when the project changes.
declare -gA _bolt_cache=()
declare -ga _bolt_names=()

# Prints a usable ruby. BOLT_COMPLETION_RUBY takes precedence, then bolt's
# bundled interpreter (all-in-one package), then the system ruby.
_bolt_ruby() {
  local r=${BOLT_COMPLETION_RUBY:-/opt/puppetlabs/bolt/bin/ruby}
  if [[ -x $r ]]; then
    printf '%s' "$r"
    return 0
  fi
  command -v ruby 2> /dev/null
}

# Applies JQEXPR (or equivalent RUBYSNIP) to JSON read from stdin; prints one
# result per line. Uses jq when available, else ruby.
_bolt_json_parse() {
  local jqexpr="$1" rubysnip="$2" ruby
  if command -v jq > /dev/null 2>&1; then
    jq -r "$jqexpr" 2> /dev/null
    return 0
  fi
  ruby=$(_bolt_ruby) || return 1
  "$ruby" -rjson -e "$rubysnip" 2> /dev/null
}

# Prints the top-level keys of a JSON file (bolt's cache files)
_bolt_complete() {
  local cur prev next=""
  # bash-completion provides word splitting for names containing colons;
  # fall back to plain words when it is not loaded
  if declare -F _get_comp_words_by_ref > /dev/null 2>&1; then
    _get_comp_words_by_ref -n : cur
    _get_comp_words_by_ref -n : prev
  else
    cur=${COMP_WORDS[COMP_CWORD]:-}
    prev=${COMP_WORDS[COMP_CWORD-1]:-}
  fi

  # Locate the subcommand and action words (skipping options and their
  # values), so forms like `bolt --project X plan run <TAB>` work
  _bolt_find_sa
  local subcommand="${_bolt_sub:-}"
  local action="${_bolt_act:-}"
  local context_opts="-m --modulepath --project"
  local global_opts="--clear-cache -h --help --log-level --version"
  local inventory_opts="-q --query --rerun -t --targets"
  local authentication_opts="-u --user -p --password --password-prompt --private-key --host-key-check --no-host-key-check --ssl --no-ssl --ssl-verify --no-ssl-verify"
  local escalation_opts="--run-as --sudo-password --sudo-password-prompt --sudo-executable"
  local run_context_opts="-c --concurrency -i --inventoryfile --save-rerun --no-save-rerun --cleanup --no-cleanup --puppetdb"
  local transport_opts="--transport --connect-timeout --tty --no-tty --native-ssh --no-native-ssh --ssh-command --copy-command"
  local choria_opts="--choria-config-file --choria-mcollective-certname --choria-ssl-ca --choria-ssl-cert --choria-ssl-key --choria-collective --choria-puppet-environment --choria-rpc-timeout --choria-task-timeout --choria-command-timeout --choria-brokers --choria-broker-timeout"
  local display_opts="--format --color --no-color -v --verbose --no-verbose --trace --stream"
  local action_opts="${inventory_opts} ${authentication_opts} ${escalation_opts} ${run_context_opts} ${context_opts} ${transport_opts} ${choria_opts} ${display_opts}"
  local apply_opts="--noop --compile-concurrency --hiera-config"
  local file_opts=" -m --modulepath --project --private-key -i --inventoryfile --hiera-config --choria-config-file "

  # Effective project for the dynamic completions (--project argument,
  # otherwise the current directory), its cache key and stamp
  _bolt_proj=$(_bolt_project)
  local projdir="${_bolt_proj:-$PWD}"
  _bolt_projkey=$(printf '%s' "$projdir" | tr -c 'a-zA-Z0-9' '_')
  _bolt_projstamp=$(_bolt_project_stamp "$projdir")

  # If there's only one word typed, complete the subcommand
  if [ $COMP_CWORD -eq 1 ]; then
    next="apply command file group guide inventory lookup module plan plugin policy project script secret task"
  # Complete files for options that accept files
  elif [[ $file_opts == *" ${prev} "* ]]; then
    next=$(compgen -f -d "" -- "$cur")
  # Handle tab completing enumerable CLI options
  elif [ "$prev" == "--log-level" ]; then
    next="trace debug info warn error fatal"
  elif [ "$prev" == "--transport" ]; then
    next="choria docker jail local lxd pcp podman remote ssh winrm"
  elif [ "$prev" == "--format" ]; then
    next="human json rainbow"
  elif [ "$prev" == "--choria-task-agent" ]; then
    next="bolt_tasks shell"
  # comma separated groups/targets, only for commands that accept targets
  elif [[ $prev == -t || $prev == --targets || $cur == --targets=* ]] && _bolt_targets_allowed; then
    _bolt_complete_targets
    return 0
  else
    # Once we have subcommands, complete actions and their arguments
    case $subcommand in
      apply)
        next="${action_opts} ${apply_opts} -e --execute"
        ;;
      command)
        if [ $COMP_CWORD -eq 2 ]; then
          next="run"
        elif [ $action = "run" ]; then
          next="${action_opts} --env-var"
        fi
        ;;
      file)
        if [ $COMP_CWORD -eq 2 ]; then
          next="download upload"
        elif [ $action = 'download' ]; then
          next="${action_opts}"
        elif [ $action = 'upload' ]; then
          next="${action_opts} --tmpdir"
        fi
        ;;
      group)
        if [ $COMP_CWORD -eq 2 ]; then
          next="show"
        elif [ $action == 'show' ]; then
          next="--project --format --inventoryfile"
        fi
        ;;
      guide)
        next="--format $( _bolt_guide_topics | tr '\n' ' ' )"
        ;;
      inventory)
        if [ $COMP_CWORD -eq 2 ]; then
          next="show"
        elif [ $action == 'show' ]; then
          next="${inventory_opts} --project --format --inventoryfile --detail"
        fi
        ;;
      lookup)
        next="${action_opts} --hiera-config --plan-hierarchy"
        ;;
      module)
        if [ $COMP_CWORD -eq 2 ]; then
          next="add generate-types install show"
        else
          case $action in
            add) next="--project";;
            generate-types) next="${context_opts}";;
            install) next="--project --force --resolve";;
            show) next="${context_opts}";;
          esac
        fi
        ;;
      plan)
        case $action in
          convert)
            _bolt_entity_slot plans plan "${context_opts}" no-params
            ;;
          new)
            next="--project --pp"
            ;;
          run)
            _bolt_entity_slot plans plan "${action_opts} --params --compile-concurrency --tmpdir --hiera-config" || return 0
            ;;
          show)
            _bolt_entity_slot plans plan "${context_opts} --filter --format" no-params
            ;;
          *) next="convert new run show";;
        esac
        ;;
      plugin)
        if [ $COMP_CWORD -eq 2 ]; then
          next="show"
        elif [ $action == 'show' ]; then
          next="${context_opts} --format --color --no-color"
        fi
        ;;
      policy)
        if [ $COMP_CWORD -eq 2 ]; then
          next="apply new show"
        else
          case $action in
            apply) next="${action_opts} --noop --compile-concurrency --hiera-config";;
            new | show) next="--project";;
          esac
        fi
        ;;
      project)
        if [ $COMP_CWORD -eq 2 ]; then
          next="init migrate"
        else
          case $action in
            init) next="--modules";;
            migrate) next="--project --inventoryfile";;
          esac
        fi
        ;;
      script)
        if [ $COMP_CWORD -eq 2 ]; then
          next="run"
        elif [ $action == 'run' ]; then
          if [ $COMP_CWORD -eq 3 ]; then
            # List files and directories for the script path argument
            next=$(compgen -f -d "" -- "$cur")
          else
            next="${action_opts} --env-var --tmpdir"
          fi
        fi
        ;;
      secret)
        if [ $COMP_CWORD -eq 2 ]; then
          next="createkeys encrypt decrypt"
        else
          case $action in
            createkeys) next="${context_opts} --plugin --force";;
            encrypt | decrypt) next="${context_opts} --plugin";;
          esac
        fi
        ;;
      task)
        case $action in
          run)
            _bolt_entity_slot tasks task "${action_opts} --params --tmpdir --noop --choria-task-agent" || return 0
            ;;
          show)
            _bolt_entity_slot tasks task "${context_opts} --filter --format" no-params
            ;;
          *) next="run show";;
        esac
        ;;
    esac
  fi

  # If any of the next options are flags, we've reached the end of the
  # building-a-Bolt-command part and can re-enable Bolt's global flags.
  if [[ "$next" =~ "--" ]]; then
    next+=" ${global_opts}"
  fi

  COMPREPLY=($(compgen -W "$next" -- "$cur"))
  # Display and complete plan/task/module names sensibly when they contain
  # colons (bash-completion only)
  declare -F __ltrim_colon_completions > /dev/null 2>&1 && __ltrim_colon_completions "$cur"
}

# --- dynamic helpers (parity with resources/bolt-completion.zsh) --------------

# Locates the subcommand and action words among COMP_WORDS, skipping options
# and their values; sets _bolt_sub, _bolt_act and their word indexes
_bolt_find_sa() {
  local subactions="apply command file group guide inventory lookup module plan plugin policy project script secret task"
  local i w skip=0
  _bolt_sub=""; _bolt_act=""; _bolt_subix=0; _bolt_actix=0
  for ((i = 1; i <= COMP_CWORD; i++)); do
    w=${COMP_WORDS[$i]}
    if (( skip )); then skip=0; continue; fi
    if [[ $w == --* && $w != *=* ]]; then skip=1; continue; fi
    if [[ $w == -* || $w == *=* ]]; then continue; fi
    if ((_bolt_subix == 0)); then
      case " $subactions " in
        *" $w "*) _bolt_sub="$w"; _bolt_subix=$i; continue;;
      esac
    elif ((_bolt_actix == 0)); then
      _bolt_act="$w"; _bolt_actix=$i
      break
    fi
  done
  ((_bolt_actix)) || _bolt_actix=_bolt_subix
}

# Resolves the current word for a subcommand that takes an entity name as
# its first free argument (optionally followed by "name=value" parameters):
# LISTKIND is the name list to complete ("plans"/"tasks"), ENTITYKIND the
# singular word for parameter fetches ("plan"/"task"), OPTS the fallback
# option list. When there is no free argument yet, the current word is the
# name slot; otherwise it is a parameter slot (unless "no-params" is given).
# Looks past "--project X" and similar options.
_bolt_entity_slot() {
  local listkind=$1 entitykind=$2 opts=$3 params="${4:-}" cur=${COMP_WORDS[COMP_CWORD]:-}
  local w i name="" skip=0 found=0
  for ((i = _bolt_actix + 1; i < COMP_CWORD; i++)); do
    w=${COMP_WORDS[$i]}
    if (( skip )); then skip=0; continue; fi
    if [[ $w == --* && $w != *=* ]]; then skip=1; continue; fi
    if [[ $w == -* || $w == *=* ]]; then continue; fi
    name="$w"; found=1
    break
  done
  if (( found )); then
    if [[ $params != no-params && $cur != *=* && $cur != -* ]] && _bolt_prev_is_arg; then
      if _bolt_complete_params "$entitykind"; then
        # COMPREPLY is set, signal the caller to stop before the global
        # COMPREPLY assignment wipes it
        return 1
      fi
    fi
    next="$opts"
  elif _bolt_list_names "$listkind"; then
    next="${_bolt_names[*]}"
  else
    next="$opts"
  fi
  return 0
}

# Prints the value given to --project (or --project=VAL) anywhere in the
# command line, or nothing when the option is absent
_bolt_project() {
  local i
  for ((i = 1; i < ${#COMP_WORDS[@]}; i++)); do
    case ${COMP_WORDS[$i]} in
      --project)
        if (( (i + 1) < ${#COMP_WORDS[@]} )); then
          printf '%s' "${COMP_WORDS[$((i + 1))]}"
          return 0
        fi
        ;;
      --project=*)
        printf '%s' "${COMP_WORDS[$i]#*=}"
        return 0
        ;;
    esac
  done
}

# GNU/BSD portability for file mtimes
_bolt_stat_mtime() {
  stat -c %Y "$1" 2> /dev/null || stat -f %m "$1" 2> /dev/null
}

# Prints a change-sentinel for the effective project: the newest mtime among
# bolt-project.yaml, inventory.yaml and the first-level module directories,
# or 0 when none exist (entries are then valid for the shell session only)
_bolt_project_stamp() {
  local p="$1" m mtop=0 f dir
  for f in "$p/bolt-project.yaml" "$p/inventory.yaml"; do
    [[ -e $f ]] || continue
    m=$(_bolt_stat_mtime "$f") || continue
    ((m > mtop)) && mtop=$m
  done
  for dir in "$p/modules" "$p/bolt-modules"; do
    [[ -d $dir ]] || continue
    for f in "$dir"/*/; do
      [[ -d $f ]] || continue
      m=$(_bolt_stat_mtime "$f") || continue
      ((m > mtop)) && mtop=$m
    done
  done
  printf '%s' "$mtop"
}

# Prints the cache key for KIND, incorporating the project key and stamp
_bolt_cache_key() {
  printf '%s|%s|%s' "$1" "$_bolt_projkey" "$_bolt_projstamp"
}

# Fetches the NAMES for KIND ('plans', 'tasks', 'groups' or 'targets') via
# `bolt plan/task/group/inventory show --format json`, using the per-project
# in-memory cache. Fills _bolt_names and returns 0 on success.
# Must not be called within a command substitution, or the cache would not
# survive.
_bolt_fetch_list() {
  local kind=$1 key cmd jsonkey jqexpr rubysnip json line
  key=$(_bolt_cache_key "$kind")
  if [[ -n ${_bolt_cache[$key]:-} ]]; then
    _bolt_names=()
    while IFS= read -r line; do _bolt_names+=("$line"); done <<< "${_bolt_cache[$key]}"
    return 0
  fi

  case $kind in
    plans)   cmd=(plan)      jsonkey=plans ;;
    tasks)   cmd=(task)      jsonkey=tasks ;;
    groups)  cmd=(group)     jsonkey=groups ;;
    targets) cmd=(inventory) jsonkey=targets ;;
  esac

  _bolt_names=()
  command -v bolt > /dev/null 2>&1 || return 1
  local proj_opts=()
  [[ -n $_bolt_proj ]] && proj_opts=(--project "$_bolt_proj")
  json=$(bolt "${cmd[@]}" show "${proj_opts[@]}" --format json 2> /dev/null)
  [[ -n $json ]] || return 1

  # plan/task lists are [["name","description"],...] pairs, the rest are
  # plain name strings
  if [[ $kind == plans || $kind == tasks ]]; then
    jqexpr=".${jsonkey}[] | .[0]"
    rubysnip="begin; JSON.parse(STDIN.read)['$jsonkey'].each { |e| puts e[0] }; rescue; end"
  else
    jqexpr=".${jsonkey}[]"
    rubysnip="begin; JSON.parse(STDIN.read)['$jsonkey'].each { |e| puts e }; rescue; end"
  fi
  mapfile -t _bolt_names < <(printf '%s' "$json" | _bolt_json_parse "$jqexpr" "$rubysnip" | sort -u)
  if (( ${#_bolt_names[@]} )); then
    _bolt_cache[$key]="$(printf '%s\n' "${_bolt_names[@]}")"
    return 0
  fi
  return 1
}

# Fetches plan/task names via `_bolt_fetch_list` and returns 1 when that
# fails (bolt unavailable or an empty project).
_bolt_list_names() {
  local kind=$1
  _bolt_names=()
  _bolt_fetch_list "$kind"
}

# Merges groups with individual targets for target completion; respects
# BOLT_COMPLETION_TARGETS. Fills _bolt_names.
_bolt_target_names() {
  local merged=()
  if _bolt_fetch_list groups; then
    merged+=("${_bolt_names[@]}")
  fi
  case ${BOLT_COMPLETION_TARGETS:-1} in
    0 | false | off | no) : ;;
    *)
      if _bolt_fetch_list targets; then
        merged+=("${_bolt_names[@]}")
      fi
      ;;
  esac
  (( ${#merged[@]} )) || return 1
  mapfile -t _bolt_names < <(printf '%s\n' "${merged[@]}" | sort -u)
  return 0
}

# Returns 0 when the current subcommand/action accepts --targets
_bolt_targets_allowed() {
  case ${subcommand:-} in
    apply | lookup)
      return 0
      ;;
    command | file | plan | script | task)
      [[ ${action:-} == run ]] && return 0
      ;;
    inventory)
      [[ ${action:-} == show ]] && return 0
      ;;
    policy)
      [[ ${action:-} == apply ]] && return 0
      ;;
  esac
  return 1
}

# Completes a comma separated list of groups/targets: completes the segment
# after the last comma, preserving the already entered part (candidates are
# built as full replacement words so bash swaps the whole value).
_bolt_complete_targets() {
  local cur="${COMP_WORDS[COMP_CWORD]:-}"
  local base="" sep="" name u is_used
  local -a used=() cands=()
  if [[ $cur == *,* ]]; then
    base="${cur%,*}"; sep=","
    read -ra used <<< "$base"
  elif [[ $cur == --targets=* ]]; then
    base="--targets="
  fi
  _bolt_target_names || return 0
  for name in "${_bolt_names[@]}"; do
    is_used=0
    if (( ${#used[@]} )); then
      for u in "${used[@]}"; do
        [[ $name == "$u" ]] && is_used=1 && break
      done
    fi
    (( is_used )) && continue
    cands+=("${base:+$base$sep}$name")
  done
  (( ${#cands[@]} )) || return 0
  COMPREPLY=($(compgen -W "${cands[*]}" -- "$cur"))
}

# Returns 0 when the current word is a free argument (not the value of a
# preceding option flag)
_bolt_prev_is_arg() {
  local prev="${COMP_WORDS[COMP_CWORD-1]:-}"
  [[ $prev == -* || $prev == *=* ]] && return 1
  return 0
}

# Completes plan/task parameters as "name=" via
# `bolt plan/task show <NAME> --format json`. Returns 0 (leaving COMPREPLY
# set) when parameters exist; the caller falls back to the option list
# otherwise.
_bolt_complete_params() {
  local kind=$1 name cur json params jqexpr rubysnip
  cur=${COMP_WORDS[COMP_CWORD]:-}

  # the entity name is the first non-option argument after the action
  local i w skip=0
  name=""
  for ((i = _bolt_actix + 1; i < COMP_CWORD; i++)); do
    w=${COMP_WORDS[$i]}
    if (( skip )); then skip=0; continue; fi
    if [[ $w == --* && $w != *=* ]]; then skip=1; continue; fi
    if [[ $w == -* || $w == *=* ]]; then continue; fi
    name="$w"; break
  done
  [[ -n $name ]] || return 1

  # parameters already given via --params: complete no more
  local given=0
  for ((i = _bolt_actix + 1; i < COMP_CWORD; i++)); do
    [[ ${COMP_WORDS[$i]} == --params || ${COMP_WORDS[$i]} == --params=* ]] && given=1
  done
  (( given )) && return 1

  command -v bolt > /dev/null 2>&1 || return 1
  local proj_opts=()
  [[ -n $_bolt_proj ]] && proj_opts=(--project "$_bolt_proj")
  json=$(bolt "$kind" show "$name" "${proj_opts[@]}" --format json 2> /dev/null)
  [[ -n $json ]] || return 1

  if [[ $kind == plan ]]; then
    jqexpr='.parameters // {} | keys | .[]'
    rubysnip="begin; ps = JSON.parse(STDIN.read)['parameters']; ps.is_a?(Hash) and ps.each_key { |k| puts k }; rescue; end"
  else
    jqexpr='.metadata.parameters // {} | keys | .[]'
    rubysnip="begin; ps = JSON.parse(STDIN.read)['metadata']['parameters']; ps.is_a?(Hash) and ps.each_key { |k| puts k }; rescue; end"
  fi
  params=$(printf '%s' "$json" | _bolt_json_parse "$jqexpr" "$rubysnip" | sort -u)
  # An error response (unknown plan/task) has no parameters key, the '// {}'
  # guard then yields no names; a real task with zero parameters yields no
  # candidates either — in both cases fall back to the option list
  [[ -n $params ]] || return 1
  COMPREPLY=($(compgen -W "$(_bolt_params_with_eq "$params")" -- "${cur%%=*}"))
  return 0
}

# Prints a space-separated "name=" list from a newline-separated params list
_bolt_params_with_eq() {
  local out="" p
  while read -r p; do
    [[ -n $p ]] && out+="${p}= "
  done <<< "$1"
  printf '%s' "${out% }"
}

# Prints the static OpenBolt guide topics
_bolt_guide_topics() {
  printf '%s\n' debugging inventory links logging module modulepath project targets transports
}

complete -F _bolt_complete bolt
