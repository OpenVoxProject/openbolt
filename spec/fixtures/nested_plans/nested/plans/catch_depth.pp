plan nested::catch_depth (
  Integer $levels,
) {
  if $levels > 0 {
    run_plan('nested::catch_depth', levels => $levels - 1, '_catch_errors' => true)
  }
  return('finished')
}
