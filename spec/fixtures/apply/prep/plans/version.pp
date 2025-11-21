plan prep::version(TargetSpec $nodes) {
  $nodes.apply_prep

  return run_task("openvox_bootstrap::check", $nodes)
}
