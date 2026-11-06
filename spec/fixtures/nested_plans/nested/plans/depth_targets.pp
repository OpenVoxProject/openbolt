plan nested::depth_targets (
  TargetSpec $targets,
  Integer $levels,
) {
  if $levels > 0 {
    return(run_plan('nested::depth_targets', $targets, levels => $levels - 1))
  }
  return('bottom')
}
