# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'
require 'bolt/inventory'
require 'bolt/result'
require 'bolt/result_set'
require 'bolt/target'
require 'puppet/pops/types/p_sensitive_type'
require 'rspec/expectations'

class TaskTypeMatcher
  def initialize(executable, input_method)
    @executable = Regexp.new(executable)
    @input_method = input_method
  end

  # rspec-mocks uses #=== to check whether an actual argument matches.
  def ===(other)
    @executable =~ other.files.first['path'] && @input_method == other.metadata['input_method']
  end
end

describe 'run_task' do
  include SpecFixtures

  let(:executor) { Bolt::Executor.new }
  let(:inventory) { Bolt::Inventory.empty }
  let(:tasks_enabled) { true }

  before(:each) do
    Puppet[:tasks] = tasks_enabled
    allow(executor).to receive(:noop).and_return(false)

    Puppet.push_context(bolt_executor: executor, bolt_inventory: inventory)
  end

  after(:each) do
    Puppet.pop_context
  end

  def mock_task(executable, input_method)
    TaskTypeMatcher.new(executable, input_method)
  end

  context 'it calls bolt executor run_task' do
    let(:hostname) { 'a.b.com' }
    let(:hostname2) { 'x.y.com' }
    let(:message) { 'the message' }
    let(:target) { inventory.get_target(hostname) }
    let(:target2) { inventory.get_target(hostname2) }
    let(:result) { Bolt::Result.new(target, value: { '_output' => message }) }
    let(:result2) { Bolt::Result.new(target2, value: { '_output' => message }) }
    let(:result_set) { Bolt::ResultSet.new([result]) }
    let(:tasks_root) { File.expand_path(fixtures('modules', 'test', 'tasks')) }
    let(:default_args) { { 'message' => message } }

    it 'when running a task without metadata the input method is "both"' do
      executable = File.join(tasks_root, 'echo.sh')

      expect(executor).to receive(:run_task)
              .with([target], mock_task(executable, nil), default_args, {}, [])
              .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('Test::Echo', hostname, default_args)
        .and_return(result_set)
    end

    it 'when running a task with metadata - the input method is specified by the metadata' do
      executable = File.join(tasks_root, 'meta.sh')

      expect(executor).to receive(:run_task)
              .with([target], mock_task(executable, 'environment'), default_args, {}, [])
              .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('Test::Meta', hostname, default_args)
        .and_return(result_set)
    end

    it 'when called with _run_as - _run_as is passed to the executor' do
      executable = File.join(tasks_root, 'meta.sh')

      expect(executor).to receive(:run_task)
              .with([target], mock_task(executable, 'environment'), default_args, { run_as: 'root' }, [])
              .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      args = default_args.merge('_run_as' => 'root')
      is_expected.to run
        .with_params('Test::Meta', hostname, args)
        .and_return(result_set)
    end

    it 'when called without without args hash (for a task where this is allowed)' do
      executable = File.join(tasks_root, 'yes.sh')

      expect(executor).to receive(:run_task)
              .with([target], mock_task(executable, nil), {}, {}, [])
              .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('test::yes', hostname)
        .and_return(result_set)
    end

    it 'uses the default if a parameter is not specified' do
      executable = File.join(tasks_root, 'params.sh')
      args = {
        'mandatory_string' => 'str',
        'mandatory_integer' => 10,
        'mandatory_boolean' => true
      }

      expected_args = args.merge('default_string' => 'hello', 'optional_default_string' => 'goodbye')
      expect(executor).to receive(:run_task)
              .with([target], mock_task(executable, 'stdin'), expected_args, {}, [])
              .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('Test::Params', hostname, args)
    end

    it 'does not use the default if a parameter is specified' do
      executable = File.join(tasks_root, 'params.sh')
      args = {
        'mandatory_string' => 'str',
        'mandatory_integer' => 10,
        'mandatory_boolean' => true,
        'default_string' => 'something',
        'optional_default_string' => 'something else'
      }

      expect(executor).to receive(:run_task)
              .with([target], mock_task(executable, 'stdin'), args, {}, [])
              .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('Test::Params', hostname, args)
    end

    it 'uses the default if a parameter is specified as undef' do
      executable = File.join(tasks_root, 'undef.sh')
      args = {
        'undef_default'    => nil,
        'undef_no_default' => nil
      }
      expected_args = {
        'undef_default'    => 'foo',
        'undef_no_default' => nil
      }

      expect(executor).to receive(:run_task)
              .with([target], mock_task(executable, 'environment'), expected_args, {}, [])
              .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('test::undef', hostname, args)
        .and_return(result_set)
    end

    it 'when called with no destinations - does not invoke bolt' do
      expect(executor).not_to receive(:run_task)
      expect(inventory).to receive(:get_targets).with([]).and_return([])

      is_expected.to run
        .with_params('Test::Yes', [])
        .and_return(Bolt::ResultSet.new([]))
    end

    it 'reports the function call and task name to analytics' do
      expect(executor).to receive(:report_function_call).with('run_task')
      expect(executor).to receive(:report_bundled_content).with('Task', 'Test::Echo').once
      executable = File.join(tasks_root, 'echo.sh')

      expect(executor).to receive(:run_task)
              .with([target], mock_task(executable, nil), default_args, {}, [])
              .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('Test::Echo', hostname, default_args)
        .and_return(result_set)
    end

    it 'skips reporting the function call to analytics if called internally from Bolt' do
      expect(executor).not_to receive(:report_function_call).with('run_task')
      executable = File.join(tasks_root, 'echo.sh')

      expect(executor).to receive(:run_task)
              .with([target], mock_task(executable, nil), default_args, kind_of(Hash), [])
              .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('Test::Echo', hostname, default_args.merge('_bolt_api_call' => true))
        .and_return(result_set)
    end

    context 'without tasks enabled' do
      let(:tasks_enabled) { false }

      it 'fails and reports that run_task is not available' do
        is_expected.to run
          .with_params('Test::Echo', hostname)
          .and_raise_error(/Plan language function 'run_task' cannot be used/)
      end
    end

    context 'with description' do
      let(:message) { 'test message' }

      it 'passes the description through if parameters are passed' do
        expect(executor).to receive(:run_task)
                .with([target], anything, {}, { description: message }, [])
                .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

        is_expected.to run
          .with_params('test::yes', hostname, message, {})
      end

      it 'passes the description through if no parameters are passed' do
        expect(executor).to receive(:run_task)
                .with([target], anything, {}, { description: message }, [])
                .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

        is_expected.to run
          .with_params('test::yes', hostname, message)
      end
    end

    context 'without description' do
      it 'ignores description if parameters are passed' do
        expect(executor).to receive(:run_task)
                .with([target], anything, {}, {}, [])
                .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

        is_expected.to run
          .with_params('test::yes', hostname, {})
      end

      it 'ignores description if no parameters are passed' do
        expect(executor).to receive(:run_task)
                .with([target], anything, {}, {}, [])
                .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

        is_expected.to run
          .with_params('test::yes', hostname)
      end
    end

    context 'with multiple destinations' do
      let(:result_set) { Bolt::ResultSet.new([result, result2]) }

      it 'targets can be specified as repeated nested arrays and strings and combine into one list of targets' do
        executable = File.join(tasks_root, 'meta.sh')

        expect(executor).to receive(:run_task)
                .with([target, target2], mock_task(executable, 'environment'), default_args, {}, [])
                .and_return(result_set)
        expect(inventory).to receive(:get_targets).with([hostname, [[hostname2]], []]).and_return([target, target2])

        is_expected.to run
          .with_params('Test::Meta', [hostname, [[hostname2]], []], default_args)
          .and_return(result_set)
      end

      it 'targets can be specified as repeated nested arrays and Targets and combine into one list of targets' do
        executable = File.join(tasks_root, 'meta.sh')

        expect(executor).to receive(:run_task)
                .with([target, target2], mock_task(executable, 'environment'), default_args, {}, [])
                .and_return(result_set)
        expect(inventory).to receive(:get_targets).with([target, [[target2]], []]).and_return([target, target2])

        is_expected.to run
          .with_params('Test::Meta', [target, [[target2]], []], default_args)
          .and_return(result_set)
      end

      context 'when a command fails on one target' do
        let(:failresult) { Bolt::Result.new(target2, error: { 'msg' => 'oops' }) }
        let(:result_set) { Bolt::ResultSet.new([result, failresult]) }

        it 'errors by default' do
          executable = File.join(tasks_root, 'meta.sh')

          expect(executor).to receive(:run_task)
                  .with([target, target2], mock_task(executable, 'environment'), default_args, {}, [])
                  .and_return(result_set)
          expect(inventory).to receive(:get_targets).with([hostname, hostname2]).and_return([target, target2])

          is_expected.to run
            .with_params('Test::Meta', [hostname, hostname2], default_args)
            .and_raise_error(Bolt::RunFailure)
        end

        it 'does not error with _catch_errors' do
          executable = File.join(tasks_root, 'meta.sh')

          expect(executor).to receive(:run_task).with([target, target2],
                                           mock_task(executable, 'environment'),
                                           default_args,
                                           { catch_errors: true },
                                           [])
                  .and_return(result_set)
          expect(inventory).to receive(:get_targets).with([hostname, hostname2]).and_return([target, target2])

          args = default_args.merge('_catch_errors' => true)
          is_expected.to run
            .with_params('Test::Meta', [hostname, hostname2], args)
        end
      end
    end

    context 'when called on a module that contains manifests/init.pp' do
      it 'the call does not load init.pp' do
        expect(executor).not_to receive(:run_task)
        expect(inventory).to receive(:get_targets).with([]).and_return([])

        is_expected.to run
          .with_params('test::echo', [])
      end
    end

    context 'when called on a module that contains tasks/init.sh' do
      it 'finds task named after the module' do
        executable = File.join(tasks_root, 'init.sh')

        expect(executor).to receive(:run_task)
                .with([target], mock_task(executable, nil), {}, {}, [])
                .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

        is_expected.to run
          .with_params('test', hostname)
          .and_return(result_set)
      end
    end

    it 'when called with non existing task - reports an unknown task error' do
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('test::nonesuch', hostname)
        .and_raise_error(
          /Could not find a task named 'test::nonesuch'/
        )
    end

    context 'with sensitive data parameters' do
      let(:sensitive) { Puppet::Pops::Types::PSensitiveType::Sensitive }
      let(:sensitive_string) { '$up3r$ecr3t!' }
      let(:sensitive_array) { [1, 2, 3] }
      let(:sensitive_hash) { { 'k' => 'v' } }
      let(:sensitive_json) { "#{sensitive_string}\n#{sensitive_array}\n{\"k\":\"v\"}\n" }
      let(:result) { Bolt::Result.new(target, value: { '_output' => sensitive_json }) }
      let(:result_set) { Bolt::ResultSet.new([result]) }
      let(:task_params) { {} }

      it 'with Sensitive metadata - input parameters are wrapped in Sensitive' do
        executable = File.join(tasks_root, 'sensitive_meta.sh')
        input_params = {
          'sensitive_string' => sensitive_string,
          'sensitive_array' => sensitive_array,
          'sensitive_hash' => sensitive_hash
        }

        expected_params = {
          'sensitive_string' => sensitive.new(sensitive_string),
          'sensitive_array' => sensitive.new(sensitive_array),
          'sensitive_hash' => sensitive.new(sensitive_hash)
        }

        expect(sensitive).to receive(:new).with(input_params['sensitive_string'])
                 .and_return(expected_params['sensitive_string'])
        expect(sensitive).to receive(:new).with(input_params['sensitive_array'])
                 .and_return(expected_params['sensitive_array'])
        expect(sensitive).to receive(:new).with(input_params['sensitive_hash'])
                 .and_return(expected_params['sensitive_hash'])

        expect(executor).to receive(:run_task)
                .with([target], mock_task(executable, nil), expected_params, {}, [])
                .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

        is_expected.to run
          .with_params('Test::Sensitive_Meta', hostname, input_params)
          .and_return(result_set)
      end
    end

  end

  context 'running in parallel' do
    let(:default_args) { { 'message' => 'Krabby patty' } }
    let(:future) { double('future') }
    let(:hostname) { 'a.b.com' }
    let(:result) { Bolt::Result.new(target, value: { '_output' => 'Krabby patty' }) }
    let(:result_set) { Bolt::ResultSet.new([result]) }
    let(:target) { inventory.get_target(hostname) }
    let(:task) { mock_task(File.join(tasks_root, 'echo.sh'), nil) }
    let(:tasks_root) { File.expand_path(fixtures('modules', 'test', 'tasks')) }

    it 'executes in a thread if the executor is in parallel mode' do
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      expect(executor).to receive(:in_parallel?).and_return(true)
      expect(executor).to receive(:run_in_thread).and_return(result_set)

      is_expected.to run
        .with_params('Test::Echo', hostname, default_args)
        .and_return(result_set)
    end
  end

  context 'it validates the task parameters' do
    let(:task_name) { 'Test::Params' }
    let(:hostname) { 'a.b.com' }
    let(:target) { inventory.get_target(hostname) }
    let(:task_params) { {} }

    it 'errors when unknown parameters are specified' do
      task_params.merge!(
        'foo' => 'foo',
        'bar' => 'bar'
      )

      is_expected.to run
        .with_params(task_name, hostname, task_params)
        .and_raise_error(
          Puppet::ParseError,
          %r{Task\ test::params:\n
           \s*has\ no\ parameter\ named\ 'foo'\n
           \s*has\ no\ parameter\ named\ 'bar'}x
        )
    end

    it 'errors when required parameters are not specified' do
      task_params['mandatory_string'] = 'str'

      is_expected.to run
        .with_params(task_name, hostname, task_params)
        .and_raise_error(
          Puppet::ParseError,
          %r{Task\ test::params:\n
           \s*expects\ a\ value\ for\ parameter\ 'mandatory_integer'\n
           \s*expects\ a\ value\ for\ parameter\ 'mandatory_boolean'}x
        )
    end

    it "errors when the specified parameter values don't match the expected data types" do
      task_params.merge!(
        'mandatory_string' => 'str',
        'mandatory_integer' => 10,
        'mandatory_boolean' => 'str',
        'optional_string' => 10
      )

      is_expected.to run
        .with_params(task_name, hostname, task_params)
        .and_raise_error(
          Puppet::ParseError,
          %r{Task\ test::params:\n
           \s*parameter\ 'mandatory_boolean'\ expects\ a\ Boolean\ value,\ got\ String\n
           \s*parameter\ 'optional_string'\ expects\ a\ value\ of\ type\ Undef\ or\ String,
                                          \ got\ Integer}x
        )
    end

    it 'errors when the specified parameter values are outside of the expected ranges' do
      task_params.merge!(
        'mandatory_string' => '0123456789a',
        'mandatory_integer' => 10,
        'mandatory_boolean' => true,
        'optional_integer' => 10
      )

      is_expected.to run
        .with_params(task_name, hostname, task_params)
        .and_raise_error(
          Puppet::ParseError,
          %r{Task\ test::params:\n
           \s*parameter\ 'mandatory_string'\ expects\ a\ String\[1,\ 10\]\ value,\ got\ String\n
           \s*parameter\ 'optional_integer'\ expects\ a\ value\ of\ type\ Undef\ or\ Integer\[-5,\ 5\],
                                           \ got\ Integer\[10,\ 10\]}x
        )
    end

    it "errors when a specified parameter value is not Data" do
      task_params.merge!(
        'mandatory_string' => 'str',
        'mandatory_integer' => 10,
        'mandatory_boolean' => true,
        'optional_hash' => { now: Time.now }
      )

      is_expected.to run
        .with_params(task_name, hostname, task_params)
        .and_raise_error(
          Puppet::ParseError, /Task parameters are not of type Data. run_task()/
        )
    end
  end
end
