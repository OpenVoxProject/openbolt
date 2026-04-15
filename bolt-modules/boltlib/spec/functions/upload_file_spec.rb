# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'
require 'bolt/result'
require 'bolt/result_set'
require 'bolt/target'

describe 'upload_file' do
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

  context 'it calls bolt executor upload_file' do
    let(:hostname) { 'test.example.com' }
    let(:target) { Bolt::Target.new(hostname) }

    let(:message) { 'uploaded' }
    let(:result) { Bolt::Result.new(target, message: message) }
    let(:result_set) { Bolt::ResultSet.new([result]) }
    let(:module_root) { File.expand_path(fixtures('modules', 'test')) }
    let(:full_path) { File.join(module_root, 'files/uploads/index.html') }
    let(:full_dir_path) { File.dirname(full_path) }
    let(:destination) { '/var/www/html' }

    before(:each) do
      allow(Puppet.features).to receive(:bolt?).and_return(true)
    end

    it 'with fully resolved path of file and destination' do
      expect(executor).to receive(:upload_file)
        .with([target], full_path, destination, {}, [])
        .and_return(result_set)
      allow(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('test/uploads/index.html', destination, hostname)
        .and_return(result_set)
    end

    it 'with fully resolved path of directory and destination' do
      expect(executor).to receive(:upload_file)
        .with([target], full_dir_path, destination, {}, [])
        .and_return(result_set)
      allow(inventory).to receive(:get_targets).with(hostname).and_return([target])

      is_expected.to run
        .with_params('test/uploads', destination, hostname)
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
            .with_params('with_scripts/hostname.sh', destination, hostname)
            .and_raise_error(/No such file or directory: .*with_scripts.*hostname\.sh/)
        end

        it 'loads from files/' do
          full_path = File.join(module_root, 'with_files/files/hostname.sh')

          expect(executor).to receive(:upload_file)
            .with([target], full_path, destination, {}, [])
            .and_return(result_set)

          is_expected.to run
            .with_params('with_files/hostname.sh', destination, hostname)
            .and_return(result_set)
        end
      end

      context 'with scripts/ specified' do
        # hostname.sh is in with_both/files/scripts/ and with_both/scripts/
        it 'prefers loading from files/scripts/' do
          # Path that should be loaded from
          full_path = File.join(module_root, 'with_both/files/scripts/hostname.sh')

          expect(executor).to receive(:upload_file)
            .with([target], full_path, destination, {}, [])
            .and_return(result_set)

          is_expected.to run
            .with_params('with_both/scripts/hostname.sh', destination, hostname)
            .and_return(result_set)
        end

        it 'falls back to scripts/ if not found in files/' do
          # Path that should be loaded from
          full_path = File.join(module_root, 'with_scripts/scripts/hostname.sh')

          expect(executor).to receive(:upload_file)
            .with([target], full_path, destination, {}, [])
            .and_return(result_set)

          is_expected.to run
            .with_params('with_scripts/scripts/hostname.sh', destination, hostname)
            .and_return(result_set)
        end
      end

      context 'with files/ specified' do
        it 'prefers loading from files/files/' do
          # Path that should be loaded from
          full_path = File.join(module_root, 'with_files/files/files/hostname.sh')

          expect(executor).to receive(:upload_file)
            .with([target], full_path, destination, {}, [])
            .and_return(result_set)

          is_expected.to run
            .with_params('with_files/files/hostname.sh', destination, hostname)
            .and_return(result_set)
        end

        it 'falls back to files/ if enabled' do
          # Path that should be loaded from
          full_path = File.join(module_root, 'with_files/files/toplevel.sh')

          expect(executor).to receive(:upload_file)
            .with([target], full_path, destination, {}, [])
            .and_return(result_set)

          is_expected.to run
            .with_params('with_files/files/toplevel.sh', destination, hostname)
            .and_return(result_set)
        end
      end
    end

    it 'with target specified as a Target' do
      expect(executor).to receive(:upload_file)
        .with([target], full_dir_path, destination, {}, [])
        .and_return(result_set)
      allow(inventory).to receive(:get_targets).with(target).and_return([target])

      is_expected.to run
        .with_params('test/uploads', destination, target)
        .and_return(result_set)
    end

    it 'runs as another user' do
      expect(executor).to receive(:upload_file)
        .with([target], full_dir_path, destination, { run_as: 'soandso' }, [])
        .and_return(result_set)
      allow(inventory).to receive(:get_targets).with(target).and_return([target])

      is_expected.to run
        .with_params('test/uploads', destination, target, '_run_as' => 'soandso')
        .and_return(result_set)
    end

    it 'reports the call to analytics' do
      expect(executor).to receive(:upload_file)
        .with([target], full_path, destination, {}, [])
        .and_return(result_set)
      allow(inventory).to receive(:get_targets).with(hostname).and_return([target])
      expect(executor).to receive(:report_function_call).with('upload_file')

      is_expected.to run
        .with_params('test/uploads/index.html', destination, hostname)
        .and_return(result_set)
    end

    context 'with description' do
      let(:message) { 'test message' }

      it 'passes the description through if parameters are passed' do
        expect(executor).to receive(:upload_file)
          .with([target], full_dir_path, destination, { description: message }, [])
          .and_return(result_set)
        allow(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params('test/uploads', destination, target, message, {})
          .and_return(result_set)
      end

      it 'passes the description through if no parameters are passed' do
        expect(executor).to receive(:upload_file)
          .with([target], full_dir_path, destination, { description: message }, [])
          .and_return(result_set)
        allow(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params('test/uploads', destination, target, message)
          .and_return(result_set)
      end
    end

    context 'without description' do
      it 'ignores description if parameters are passed' do
        expect(executor).to receive(:upload_file)
          .with([target], full_dir_path, destination, {}, [])
          .and_return(result_set)
        allow(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params('test/uploads', destination, target, {})
          .and_return(result_set)
      end

      it 'ignores description if no parameters are passed' do
        expect(executor).to receive(:upload_file)
          .with([target], full_dir_path, destination, {}, [])
          .and_return(result_set)
        allow(inventory).to receive(:get_targets).with(target).and_return([target])

        is_expected.to run
          .with_params('test/uploads', destination, target)
          .and_return(result_set)
      end
    end

    context 'with multiple destinations' do
      let(:hostname2) { 'test.testing.com' }
      let(:target2) { Bolt::Target.new(hostname2) }
      let(:message2) { 'received' }
      let(:result2) { Bolt::Result.new(target2, message: message2) }
      let(:result_set) { Bolt::ResultSet.new([result, result2]) }

      it 'propagates multiple hosts and returns multiple results' do
        expect(executor).to receive(:upload_file)
          .with([target, target2], full_path, destination, {}, [])
          .and_return(result_set)
        allow(inventory).to receive(:get_targets).with([hostname, hostname2]).and_return([target, target2])

        is_expected.to run.with_params('test/uploads/index.html', destination, [hostname, hostname2])
                          .and_return(result_set)
      end

      context 'when upload fails on one target' do
        let(:result2) { Bolt::Result.new(target2, error: { 'msg' => 'oops' }) }

        it 'errors by default' do
          expect(executor).to receive(:upload_file)
            .with([target, target2], full_path, destination, {}, [])
            .and_return(result_set)
          expect(inventory).to receive(:get_targets).with([hostname, hostname2]).and_return([target, target2])

          is_expected.to run
            .with_params('test/uploads/index.html', destination, [hostname, hostname2])
            .and_raise_error(Bolt::RunFailure)
        end

        it 'does not error with _catch_errors' do
          expect(executor).to receive(:upload_file)
            .with([target, target2], full_path, destination, { catch_errors: true }, [])
            .and_return(result_set)
          expect(inventory).to receive(:get_targets).with([hostname, hostname2]).and_return([target, target2])

          is_expected.to run
            .with_params('test/uploads/index.html', destination, [hostname, hostname2], '_catch_errors' => true)
        end
      end
    end

    it 'without targets - does not invoke bolt' do
      expect(executor).not_to receive(:upload_file)
      expect(inventory).to receive(:get_targets).with([]).and_return([])

      is_expected.to run.with_params('test/uploads/index.html', destination, [])
                        .and_return(Bolt::ResultSet.new([]))
    end

    it 'errors when file is not found' do
      expect(executor).not_to receive(:upload_file)

      is_expected.to run.with_params('test/uploads/nonesuch.html', destination, [])
                        .and_raise_error(/No such file or directory: .*nonesuch\.html/)
    end
  end

  context 'running in parallel' do
    let(:future) { double('future') }
    let(:hostname) { 'test.example.com' }
    let(:target) { Bolt::Target.new(hostname) }
    let(:result) { Bolt::Result.new(target, value: { 'stdout' => hostname }) }
    let(:result_set) { Bolt::ResultSet.new([result]) }
    let(:destination) { '/var/www/html' }

    it 'executes in a thread if the executor is in parallel mode' do
      expect(inventory).to receive(:get_targets).with(hostname).and_return([target])

      expect(executor).to receive(:in_parallel?).and_return(true)
      expect(executor).to receive(:run_in_thread).and_return(result_set)

      is_expected.to run
        .with_params('test/uploads/index.html', destination, hostname)
        .and_return(result_set)
    end
  end

  context 'without tasks enabled' do
    let(:tasks_enabled) { false }

    it 'fails and reports that upload_file is not available' do
      is_expected.to run.with_params('test/uploads/nonesuch.html', '/some/place', [])
                        .and_raise_error(/Plan language function 'upload_file' cannot be used/)
    end
  end
end
