plan nested::depth (
  Integer $levels,
) {
  if $levels > 0 {
    return(run_plan('nested::depth', levels => $levels - 1))
  }
  return('bottom')
}
