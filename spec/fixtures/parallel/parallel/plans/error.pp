plan parallel::error(
  TargetSpec $targets
) {
  $ts = get_targets($targets)
  parallelize($ts) |$t| {
    if $t.port == 20025 {
      run_task('error::fail', $t)
    } else {
      run_task('parallel', $t, 'time' => 0, 'val' => 'a')
    }
  }

  return "We shouldn't get here"
}
