
# Save this script as _bolt in a directory listed in $fpath, or load it with
# source after compinit.

# Prints the plan or task names in OpenBolt's cache file $1 (.plan_cache.json
# or .task_cache.json) of the project in the current directory, or else of
# the default project.
_bolt_cached_names() {
  local file ruby=/opt/puppetlabs/bolt/bin/ruby
  [[ -x $ruby ]] || ruby=ruby
  for file in $PWD/$1 $HOME/.puppetlabs/bolt/$1; do
    if [[ -f $file ]]; then
      $ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).keys' $file 2>/dev/null
      return
    fi
  done
}

# Offers the words after the first two arguments, each with the description
# stored under the prefix $2 plus the word
_bolt_describe() {
  local tag=$1 prefix=$2 word
  local -a entries
  shift 2
  for word; do
    entries+=("$word:$_bolt_descriptions[$prefix$word]")
  done
  _describe -t $tag $tag entries
}

_bolt() {
  local cur=$words[CURRENT] prev=$words[CURRENT-1]

  if (( ${+_bolt_values[$prev]} )); then
    if [[ -n $_bolt_values[$prev] ]]; then
      compadd -- ${=_bolt_values[$prev]}
    else
      _files
    fi
    return
  fi

  local subcommand= action= word
  integer i positionals=0
  for ((i = 2; i < CURRENT; i++)); do
    word=$words[i]
    if [[ $word == -* ]]; then
      (( ${+_bolt_values[$word]} )) && (( i++ ))
    elif [[ -z $subcommand ]]; then
      subcommand=$word
    elif [[ -z $action && -n $_bolt_actions[$subcommand] ]]; then
      action=$word
    else
      (( ++positionals ))
    fi
  done

  local key=$subcommand${action:+ $action}
  local -a names
  if [[ $cur == -* ]]; then
    _bolt_describe options '' ${=${_bolt_options[$key]:-$_bolt_globals}}
  elif [[ -z $subcommand ]]; then
    _bolt_describe commands '' ${=_bolt_commands}
  elif [[ -n $_bolt_actions[$subcommand] && -z $action ]]; then
    _bolt_describe actions "$subcommand " ${=_bolt_actions[$subcommand]}
  else
    if (( positionals == 0 )); then
      case $key in
        guide) names=(${=_bolt_guides}) ;;
        'plan convert' | 'plan run' | 'plan show') names=($(_bolt_cached_names .plan_cache.json)) ;;
        'task run' | 'task show') names=($(_bolt_cached_names .task_cache.json)) ;;
      esac
    fi
    compadd -a names || _files
  fi
}

if [[ $funcstack[1] == _bolt ]]; then
  _bolt "$@"
else
  compdef _bolt bolt
fi
