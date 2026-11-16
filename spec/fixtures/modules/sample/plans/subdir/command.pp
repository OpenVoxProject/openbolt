plan sample::subdir::command (
  TargetSpec        $targets,
  Optional[Boolean] $stream = undef
) {
  $options = if $stream == undef {
    {}
  } else {
    { '_stream' => $stream }
  }

  return run_command('echo From subdir', $targets, $options)
}
