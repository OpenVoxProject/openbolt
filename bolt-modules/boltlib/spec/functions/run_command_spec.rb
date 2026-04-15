# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'
require 'bolt/result'
require 'bolt/result_set'
require 'bolt/target'

describe 'run_command' do
  let(:executor) { Bolt::Executor.new }
  let(:inventory) { double('inventory') }
  let(:tasks_enabled) { true }

  before(:each) do
    Puppet[:tasks] = tasks_enabled
    allow(inventory).to receive_messages(version: 2, target_implementation_class: Bolt::Target)
    Puppet.push_context(bolt_executor: executor, bolt_inventory: inventory)
  end

  after(:each) do
    Puppet.pop_context
  end

  context 'it calls bolt executor run_command' do
    let(:hostname) { 'test.example.com' }
    let(:target) { Bolt::Target.new(hostname) }
    let(:command) { 'hostname' }
    let(:result) { Bolt::Result.new(target, value: { 'stdout' => hostname }) }
    let(:result_set) { Bolt::ResultSet.new([result]) }

    before(:each) do
      allow(Puppet.features).to receive(:bolt?).and_return(true)
    end

    it 'with given command and host' do
      expect(executor).to receive(:run_command)
        .with([target], command, {}, [])
        .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params(command, hostname)
        .and_return(result_set)
    end

    it 'with given command and Target' do
      expect(executor).to receive(:run_command)
        .with([target], command, {}, [])
        .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(target).and_return([target])

      is_expected.to run
        .with_params(command, target)
        .and_return(result_set)
    end

    it 'with _run_as' do
      expect(executor).to receive(:run_command)
        .with([target], command, { run_as: 'root' }, [])
        .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(target).and_return([target])

      is_expected.to run
        .with_params(command, target, '_run_as' => 'root')
        .and_return(result_set)
    end

    it 'reports the call to analytics' do
      expect(executor).to receive(:report_function_call).with('run_command')
      expect(executor).to receive(:run_command)
        .with([target], command, {}, [])
        .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params(command, hostname)
        .and_return(result_set)
    end

    context 'with description' do
      let(:message) { 'test message' }

      it 'passes the description through if parameters are passed' do
        expect(executor).to receive(:run_command)
          .with([target], command, { description: message }, [])
          .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params(command, target, message, {})
          .and_return(result_set)
      end

      it 'passes the description through if no parameters are passed' do
        expect(executor).to receive(:run_command)
          .with([target], command, { description: message }, [])
          .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params(command, target, message)
          .and_return(result_set)
      end
    end

    context 'without description' do
      it 'ignores description if parameters are passed' do
        expect(executor).to receive(:run_command)
          .with([target], command, {}, [])
          .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params(command, target, {})
          .and_return(result_set)
      end

      it 'ignores description if no parameters are passed' do
        expect(executor).to receive(:run_command)
          .with([target], command, {}, [])
          .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params(command, target)
          .and_return(result_set)
      end
    end

    context 'with multiple hosts' do
      let(:hostname2) { 'test.testing.com' }
      let(:target2) { Bolt::Target.new(hostname2) }
      let(:result2) { Bolt::Result.new(target2, value: { 'stdout' => hostname2 }) }
      let(:result_set) { Bolt::ResultSet.new([result, result2]) }

      it 'with propagates multiple hosts and returns multiple results' do
        expect(executor).to receive(:run_command)
          .with([target, target2], command, {}, [])
          .and_return(result_set)
        expect(inventory).to receive(:get_targets).with([hostname, hostname2]).and_return([target, target2])

        is_expected.to run
          .with_params(command, [hostname, hostname2])
          .and_return(result_set)
      end

      it 'with propagates multiple Targets and returns multiple results' do
        expect(executor).to receive(:run_command)
          .with([target, target2], command, {}, [])
          .and_return(result_set)
        expect(inventory).to receive(:get_targets).with([target, target2]).and_return([target, target2])

        is_expected.to run
          .with_params(command, [target, target2])
          .and_return(result_set)
      end

      context 'when a command fails on one target' do
        let(:result2) { Bolt::Result.new(target2, error: { 'message' => hostname2 }) }

        it 'errors by default' do
          expect(executor).to receive(:run_command)
            .with([target, target2], command, {}, [])
            .and_return(result_set)
          expect(inventory).to receive(:get_targets).with([target, target2]).and_return([target, target2])

          is_expected.to run
            .with_params(command, [target, target2])
            .and_raise_error(Bolt::RunFailure)
        end

        it 'does not error with _catch_errors' do
          expect(executor).to receive(:run_command)
            .with([target, target2], command, { catch_errors: true }, [])
            .and_return(result_set)
          expect(inventory).to receive(:get_targets).with([hostname, hostname2]).and_return([target, target2])

          is_expected.to run
            .with_params(command, [hostname, hostname2], '_catch_errors' => true)
        end
      end
    end

    it 'without targets - does not invoke bolt' do
      expect(executor).not_to receive(:run_command)
      expect(inventory).to receive(:get_targets).with([]).and_return([])

      is_expected.to run
        .with_params(command, [])
        .and_return(Bolt::ResultSet.new([]))
    end
  end

  context 'running in parallel' do
    let(:future) { double('future') }
    let(:hostname) { 'test.example.com' }
    let(:target) { Bolt::Target.new(hostname) }
    let(:command) { 'hostname' }
    let(:result) { Bolt::Result.new(target, value: { 'stdout' => hostname }) }
    let(:result_set) { Bolt::ResultSet.new([result]) }

    it 'executes in a thread if the executor is in parallel mode' do
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      expect(executor).to receive(:in_parallel?).and_return(true)
      expect(executor).to receive(:run_in_thread).and_return(result_set)

      is_expected.to run
        .with_params(command, hostname)
        .and_return(result_set)
    end
  end

  context 'without tasks enabled' do
    let(:tasks_enabled) { false }

    it 'fails and reports that run_command is not available' do
      is_expected.to run
        .with_params('echo hello', [])
        .and_raise_error(/Plan language function 'run_command' cannot be used/)
    end
  end

  context 'with _env_vars' do
    let(:command) { 'echo $FRUIT' }
    let(:targets) { ['localhost'] }

    it 'errors if _env_vars is not a hash' do
      is_expected.to run
        .with_params(command, targets, { '_env_vars' => 'mango' })
        .and_raise_error(/Option 'env_vars' must be a hash/)
    end

    it 'errors if _env_vars keys are not strings' do
      is_expected.to run
        .with_params(command, targets, { '_env_vars' => { 1 => 'a' } })
        .and_raise_error(/Keys for option 'env_vars' must be strings: 1/)
    end

    it 'transforms values to json' do
      env_vars = { 'FRUIT' => { 'apple' => 'banana' } }
      options  = { env_vars: env_vars.transform_values(&:to_json) }

      expect(executor).to receive(:run_command)
        .with(targets, command, options, [])
        .and_return(Bolt::ResultSet.new([]))
      expect(inventory).to receive(:get_targets)
        .with(targets)
        .and_return(targets)

      is_expected.to run
        .with_params(command, targets, { '_env_vars' => env_vars })
    end
  end
end
