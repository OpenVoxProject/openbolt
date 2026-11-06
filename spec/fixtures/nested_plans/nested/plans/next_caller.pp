plan nested::next_caller () {
  $result = run_plan('nested::next_default')
  return("caller got ${result}")
}
