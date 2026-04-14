# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'
require 'bolt/target'
require 'bolt/result'
require 'bolt/result_set'

describe 'run_script' do
  let(:executor) { Bolt::Executor.new }
  let(:inventory) { double('inventory') }
  let(:tasks_enabled) { true }
  let(:module_root) { File.expand_path(fixtures('modules', 'test')) }
  let(:full_path) { File.join(module_root, 'files/uploads/hostname.sh') }

  before(:each) do
    Puppet[:tasks] = tasks_enabled
    allow(inventory).to receive_messages(version: 2, target_implementation_class: Bolt::Target)
    Puppet.push_context(bolt_executor: executor, bolt_inventory: inventory)
  end

  after(:each) do
    Puppet.pop_context
  end

  context 'it calls bolt executor run_script' do
    let(:hostname) { 'test.example.com' }
    let(:target) { Bolt::Target.new(hostname) }
    let(:result) { Bolt::Result.new(target, value: { 'stdout' => hostname }) }
    let(:result_set) { Bolt::ResultSet.new([result]) }

    before(:each) do
      allow(Puppet.features).to receive(:bolt?).and_return(true)
    end

    it 'with fully resolved path of file' do
      expect(executor).to receive(:run_script)
        .with([target], full_path, [], {}, [])
        .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('test/uploads/hostname.sh', hostname)
        .and_return(result_set)
    end

    context 'when locating files' do
      let(:module_root) { File.expand_path(fixtures('modules')) }

      before(:each) do
        allow(inventory).to receive(:get_targets).with(hostname).and_return([target])
      end

      context 'with nonspecific module syntax' do
        it 'does not load from scripts/ subdir' do
          is_expected.to run
            .with_params('with_scripts/hostname.sh', hostname)
            .and_raise_error(/No such file or directory: .*with_scripts.*hostname\.sh/)
        end

        it 'loads from files/' do
          full_path = File.join(module_root, 'with_files/files/hostname.sh')

          expect(executor).to receive(:run_script)
            .with([target], full_path, [], {}, [])
            .and_return(result_set)

          is_expected.to run
            .with_params('with_files/hostname.sh', hostname)
            .and_return(result_set)
        end
      end

      context 'with scripts/ specified' do
        # hostname.sh is in with_both/files/scripts/ and with_both/scripts/
        it 'prefers loading from files/scripts/' do
          # Path that should be loaded from
          full_path = File.join(module_root, 'with_both/files/scripts/hostname.sh')

          expect(executor).to receive(:run_script)
            .with([target], full_path, [], {}, [])
            .and_return(result_set)

          is_expected.to run
            .with_params('with_both/scripts/hostname.sh', hostname)
            .and_return(result_set)
        end

        it 'falls back to scripts/ if not found in files/' do
          # Path that should be loaded from
          full_path = File.join(module_root, 'with_scripts/scripts/hostname.sh')

          expect(executor).to receive(:run_script)
            .with([target], full_path, [], {}, [])
            .and_return(result_set)

          is_expected.to run
            .with_params('with_scripts/scripts/hostname.sh', hostname)
            .and_return(result_set)
        end
      end

      context 'with files/ specified' do
        it 'prefers loading from files/files/' do
          # Path that should be loaded from
          full_path = File.join(module_root, 'with_files/files/files/hostname.sh')

          expect(executor).to receive(:run_script)
            .with([target], full_path, [], {}, [])
            .and_return(result_set)

          is_expected.to run
            .with_params('with_files/files/hostname.sh', hostname)
            .and_return(result_set)
        end

        it 'falls back to files/ if enabled' do
          # Path that should be loaded from
          full_path = File.join(module_root, 'with_files/files/toplevel.sh')

          expect(executor).to receive(:run_script)
            .with([target], full_path, [], {}, [])
            .and_return(result_set)

          is_expected.to run
            .with_params('with_files/files/toplevel.sh', hostname)
            .and_return(result_set)
        end
      end
    end

    it 'with host given as Target' do
      expect(executor).to receive(:run_script)
        .with([target], full_path, [], {}, [])
        .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(target).and_return([target])

      is_expected.to run
        .with_params('test/uploads/hostname.sh', target)
        .and_return(result_set)
    end

    it 'with given arguments as a hash of {arguments => [value]}' do
      expect(executor).to receive(:run_script)
        .with([target], full_path, %w[hello world], {}, [])
        .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('test/uploads/hostname.sh',
                     hostname,
                     { 'arguments' => %w[hello world] })
        .and_return(result_set)
    end

    it 'with given arguments as a hash of {arguments => []}' do
      expect(executor).to receive(:run_script)
        .with([target], full_path, [], {}, [])
        .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(target).and_return([target])

      is_expected.to run
        .with_params('test/uploads/hostname.sh', target, 'arguments' => [])
        .and_return(result_set)
    end

    it 'with pwsh_params' do
      expect(executor).to receive(:run_script)
        .with([target], full_path, [], { pwsh_params: { 'Name' => 'BoltyMcBoltface' } }, [])
        .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('test/uploads/hostname.sh',
                     hostname,
                     { 'pwsh_params' => { 'Name' => 'BoltyMcBoltface' } })
        .and_return(result_set)
    end

    it 'with _run_as' do
      expect(executor).to receive(:run_script)
        .with([target], full_path, [], { run_as: 'root' }, [])
        .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(target).and_return([target])

      is_expected.to run
        .with_params('test/uploads/hostname.sh', target, '_run_as' => 'root')
        .and_return(result_set)
    end

    it 'reports the call to analytics' do
      expect(executor).to receive(:report_function_call).with('run_script')
      expect(executor).to receive(:run_script)
        .with([target], full_path, [], {}, [])
        .and_return(result_set)
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('test/uploads/hostname.sh', hostname)
        .and_return(result_set)
    end

    context 'with description' do
      let(:message) { 'test message' }

      it 'passes the description through if parameters are passed' do
        expect(executor).to receive(:run_script)
          .with([target], full_path, [], { description: message }, [])
          .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params('test/uploads/hostname.sh', target, message, {})
      end

      it 'passes the description through if no parameters are passed' do
        expect(executor).to receive(:run_script)
          .with([target], full_path, [], { description: message }, [])
          .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params('test/uploads/hostname.sh', target, message)
      end
    end

    context 'without description' do
      it 'ignores description if parameters are passed' do
        expect(executor).to receive(:run_script)
          .with([target], full_path, [], {}, [])
          .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params('test/uploads/hostname.sh', target, {})
      end

      it 'ignores description if no parameters are passed' do
        expect(executor).to receive(:run_script)
          .with([target], full_path, [], {}, [])
          .and_return(result_set)
        expect(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params('test/uploads/hostname.sh', target)
      end
    end

    context 'with multiple destinations' do
      let(:hostname2) { 'test.testing.com' }
      let(:target2) { Bolt::Target.new(hostname2) }
      let(:result2) { Bolt::Result.new(target2, value: { 'stdout' => hostname2 }) }
      let(:result_set) { Bolt::ResultSet.new([result, result2]) }

      it 'with propagated multiple hosts and returns multiple results' do
        expect(executor).to receive(:run_script)
          .with([target, target2], full_path, [], {}, [])
          .and_return(result_set)
        expect(inventory).to receive(:get_targets).with([hostname, hostname2]).and_return([target, target2])

        is_expected.to run
          .with_params('test/uploads/hostname.sh', [hostname, hostname2])
          .and_return(result_set)
      end

      context 'when a script fails on one target' do
        let(:result2) { Bolt::Result.new(target2, error: { 'message' => hostname2 }) }

        it 'errors by default' do
          expect(executor).to receive(:run_script)
            .with([target, target2], full_path, [], {}, [])
            .and_return(result_set)
          expect(inventory).to receive(:get_targets).with([hostname, hostname2]).and_return([target, target2])

          is_expected.to run
            .with_params('test/uploads/hostname.sh', [hostname, hostname2])
            .and_raise_error(Bolt::RunFailure)
        end

        it 'does not error with _catch_errors' do
          expect(executor).to receive(:run_script)
            .with([target, target2], full_path, [], { catch_errors: true }, [])
            .and_return(result_set)
          expect(inventory).to receive(:get_targets).with([hostname, hostname2]).and_return([target, target2])

          is_expected.to run
            .with_params('test/uploads/hostname.sh', [hostname, hostname2], '_catch_errors' => true)
        end
      end
    end

    it 'without targets - does not invoke bolt' do
      expect(executor).not_to receive(:run_script)
      expect(inventory).to receive(:get_targets).with([]).and_return([])

      is_expected.to run
        .with_params('test/uploads/hostname.sh', [])
        .and_return(Bolt::ResultSet.new([]))
    end

    it 'errors when script is not found' do
      expect(executor).not_to receive(:run_script)

      is_expected.to run
        .with_params('test/uploads/nonesuch.sh', [])
        .and_raise_error(/No such file or directory: .*nonesuch\.sh/)
    end

    it 'errors when script appoints a directory' do
      expect(executor).not_to receive(:run_script)

      is_expected.to run
        .with_params('test/uploads', [])
        .and_raise_error(%r{.*/uploads is not a file})
    end
  end

  context 'running in parallel' do
    let(:future) { double('future') }
    let(:hostname) { 'test.example.com' }
    let(:target) { Bolt::Target.new(hostname) }
    let(:result) { Bolt::Result.new(target, value: { 'stdout' => hostname }) }
    let(:result_set) { Bolt::ResultSet.new([result]) }

    it 'executes in a thread if the executor is in parallel mode' do
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      expect(executor).to receive(:in_parallel?).and_return(true)
      expect(executor).to receive(:run_in_thread).and_return(result_set)

      is_expected.to run
        .with_params('test/uploads/hostname.sh', hostname)
        .and_return(result_set)
    end
  end

  context 'without tasks enabled' do
    let(:tasks_enabled) { false }

    it 'fails and reports that run_script is not available' do
      is_expected.to run
        .with_params('test/uploads/nonesuch.sh', [])
        .and_raise_error(/Plan language function 'run_script' cannot be used/)
    end
  end

  context 'with arguments and pwsh_params' do
    it 'fails' do
      is_expected.to run
        .with_params('test/uploads/script.sh', [], 'arguments' => [], 'pwsh_params' => {})
        .and_raise_error(/Cannot specify both 'arguments' and 'pwsh_params'/)
    end
  end

  it 'fails if arguments is not an array' do
    is_expected.to run
      .with_params('test/uploads/script.sh', [], 'arguments' => { 'foo' => 'bar' })
      .and_raise_error(/Option 'arguments' must be an array/)
  end

  it 'fails if pwsh_params is not a hash' do
    is_expected.to run
      .with_params('test/uploads/script.sh', [], 'pwsh_params' => %w[foo bar])
      .and_raise_error(/Option 'pwsh_params' must be a hash/)
  end

  context 'with _env_vars' do
    let(:targets) { ['localhost'] }

    it 'errors if _env_vars is not a hash' do
      is_expected.to run
        .with_params(full_path, targets, { '_env_vars' => 'value' })
        .and_raise_error(/Option 'env_vars' must be a hash/)
    end

    it 'errors if _env_vars keys are not strings' do
      is_expected.to run
        .with_params(full_path, targets, { '_env_vars' => { 1 => 'a' } })
        .and_raise_error(/Keys for option 'env_vars' must be strings: 1/)
    end

    it 'transforms values to json' do
      env_vars = { 'FRUIT' => { 'apple' => 'banana' } }
      options  = { env_vars: env_vars.transform_values(&:to_json) }

      expect(executor).to receive(:run_script)
        .with(targets, full_path, [], options, [])
        .and_return(Bolt::ResultSet.new([]))
      expect(inventory).to receive(:get_targets)
        .with(targets)
        .and_return(targets)

      is_expected.to run
        .with_params(full_path, targets, { '_env_vars' => env_vars })
    end
  end
end
