# frozen_string_literal: true

require 'timeout'

# Control the specified block execution timeout.
#
# If code in the block specified is executing longer than timeout speficied,
# then execution is cancelled and 'bolt/execution-expired' kind of an Error is raised.
#
# > **Note:** Not available in apply block
Puppet::Functions.create_function(:with_timeout) do
  # @param timeout Timeout in seconds (0 disables timeout).
  # @param block The block to control execution timeout for.
  # @return [Any] The block return value.
  # @example Raise error if the block execution takes longer that 1 minute
  #   $result = with_timeout(60) || {
  #     run_task('deploy', $target)
  #   }
  #   out::verbose('Deploy is not timed out')
  # @example Ensure the block execution takes no longer that 1 minute
  #   $result = catch_errors(['bolt/execution-expired']) || {
  #     with_timeout(60) || {
  #       run_task('deploy', $target)
  #     }
  #   }
  #   if $result =~ Error {
  #     fail_plan("Deploy task timed out", 'deploy/timed-out')
  #   } else {
  #     out::verbose('Deploy is not timed out')
  #   }
  dispatch :with_timeout do
    param 'Integer[0]', :timeout
    block_param 'Callable[0, 0]', :block
  end

  def with_timeout(timeout, &)
    unless Puppet[:tasks]
      raise Puppet::ParseErrorWithIssue
        .from_issue_and_stack(Bolt::PAL::Issues::PLAN_OPERATION_NOT_SUPPORTED_WHEN_COMPILING,
                              action: 'with_timeout')
    end

    # Send Analytics Report
    Puppet.lookup(:bolt_executor).report_function_call(self.class.name)

    Timeout.timeout(timeout, &)
  rescue Timeout::Error
    raise Bolt::Error.new('Execution expired', 'bolt/execution-expired', details: { timeout: timeout })
  end
end
