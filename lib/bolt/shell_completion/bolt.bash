
# Load this script from ~/.bashrc, or save it as
# /usr/share/bash-completion/completions/bolt. It needs bash 4.2 or later.

# Prints the plan or task names in OpenBolt's cache file $1 (.plan_cache.json
# or .task_cache.json) of the project in the current directory, or else of
# the default project.
_bolt_cached_names() {
  local file ruby=/opt/puppetlabs/bolt/bin/ruby
  [[ -x $ruby ]] || ruby=ruby
  for file in "$PWD/$1" "$HOME/.puppetlabs/bolt/$1"; do
    if [[ -f $file ]]; then
      "$ruby" -rjson -e 'puts JSON.parse(File.read(ARGV[0])).keys' "$file" 2>/dev/null
      return
    fi
  done
}

_bolt() {
  local cur prev words cword
  if declare -F _get_comp_words_by_ref >/dev/null; then
    # Keeps names such as mymodule::myplan in one word
    _get_comp_words_by_ref -n : cur prev words cword
  else
    cur=${COMP_WORDS[COMP_CWORD]}
    prev=${COMP_WORDS[COMP_CWORD - 1]}
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD
  fi

  if [[ -n ${_bolt_values[$prev]+set} ]]; then
    COMPREPLY=($(compgen -W "${_bolt_values[$prev]}" -- "$cur"))
    return
  fi

  local subcommand='' action='' word i positionals=0
  for ((i = 1; i < cword; i++)); do
    word=${words[i]}
    if [[ $word == -* ]]; then
      [[ -n ${_bolt_values[$word]+set} ]] && ((i++))
    elif [[ -z $subcommand ]]; then
      subcommand=$word
    elif [[ -z $action && -n ${_bolt_actions[$subcommand]} ]]; then
      action=$word
    else
      ((++positionals))
    fi
  done

  local key=$subcommand${action:+ $action} candidates=''
  if [[ $cur == -* ]]; then
    candidates=$_bolt_globals
    [[ -n $subcommand && -n ${_bolt_options[$key]+set} ]] && candidates=${_bolt_options[$key]}
  elif [[ -z $subcommand ]]; then
    candidates=$_bolt_commands
  elif [[ -n ${_bolt_actions[$subcommand]} && -z $action ]]; then
    candidates=${_bolt_actions[$subcommand]}
  elif ((positionals == 0)); then
    case $key in
      guide) candidates=$_bolt_guides ;;
      'plan convert' | 'plan run' | 'plan show') candidates=$(_bolt_cached_names .plan_cache.json) ;;
      'task run' | 'task show') candidates=$(_bolt_cached_names .task_cache.json) ;;
    esac
  fi

  # With no matches, bash completes file names (complete -o default)
  COMPREPLY=($(compgen -W "$candidates" -- "$cur"))
  if declare -F __ltrim_colon_completions >/dev/null; then
    __ltrim_colon_completions "$cur"
  fi
}

complete -o default -F _bolt bolt
