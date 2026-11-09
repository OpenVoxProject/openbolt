# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/choria'
require 'bolt_spec/files'
require 'bolt_spec/pal'
require 'bolt_spec/task'
require 'bolt/executor'
require 'bolt/inventory'
require 'bolt/transport/choria'
require 'digest'
require 'securerandom'
require 'tmpdir'

require 'shared_examples/transport'

# Runs against the containers acceptance:choria:up starts. choria_node1 and choria_node2 have the
# shell, file_transfer and bolt_tasks agents, and choria_node3 has only the ones Choria installs.
# boltserver is the OpenVox server the bolt_tasks agent downloads the fixture modules' tasks from.
describe Bolt::Transport::Choria do
  include BoltSpec::Choria
  include BoltSpec::Files
  include BoltSpec::Task

  # MCollective loads the config once per process, so the first example's file serves them all
  let(:client_config) do
    # The transport loads the file_transfer client library from this libdir.
    # BOLT_CHORIA_FILE_TRANSFER_LIBDIR points it at the files directory of an
    # agent checkout instead.
    libdir = ENV.fetch('BOLT_CHORIA_FILE_TRANSFER_LIBDIR') do
      File.expand_path('../../fixtures/choria/modules/mcollective_agent_file_transfer/files', __dir__)
    end
    write_choria_config(collectives: 'mcollective', main_collective: 'mcollective', connector: 'nats',
                        securityprovider: 'choria', identity: 'bolt.mcollective', libdir: libdir, loglevel: 'warn')
  end
  let(:client_ssl_dir) { File.expand_path('../../fixtures/choria/ssl/bolt.mcollective', __dir__) }
  let(:transport_config) do
    {
      'config-file' => client_config.path,
      'brokers' => 'localhost:4222',
      'mcollective-certname' => 'bolt.mcollective',
      'ssl-ca' => File.expand_path('../../fixtures/ssl/ca.pem', __dir__),
      'ssl-cert' => File.join(client_ssl_dir, 'cert.pem'),
      'ssl-key' => File.join(client_ssl_dir, 'key.pem'),
      # The shared examples write their tasks to temporary files, which the server doesn't have
      'task-agent' => 'shell',
      # The examples with a node that never answers wait this long
      'rpc-timeout' => 10
    }
  end
  let(:inventory) { Bolt::Inventory.empty }
  let(:transport) { :choria }
  let(:os_context) { posix_context }
  let(:target) { choria_target('choria_node1') }
  let(:second_target) { choria_target('choria_node2') }
  let(:target_without_agents) { choria_target('choria_node3') }
  let(:missing_target) { choria_target('choria_missing') }
  # The shared examples call the transport runner. As a let it is 1 instance per example,
  # so the nodes are discovered once
  let(:runner) { Bolt::Transport::Choria.new }

  after { client_config.close! }

  def choria_target(identity)
    node = inventory.get_target("choria://#{identity}")
    inventory.set_config(node, 'choria', transport_config)
    node
  end

  def missing_agent_error(agent)
    { 'kind' => 'bolt/choria-agent-not-available', 'msg' => "The '#{agent}' agent is not available on choria://choria_node3." }
  end

  include_examples 'transport api'

  it 'sets environment variables for a script' do
    with_tempfile_containing('script', "#!/bin/sh\nprintenv BOLT_TEST_VAR", '.sh') do |file|
      result = runner.batch_script([target], file.path, [], env_vars: { 'BOLT_TEST_VAR' => 'hello world' }).first
      expect(result['stdout']).to eq("hello world\n")
    end
  end

  context 'with a node without the OpenBolt agents' do
    it 'fails a command' do
      result = runner.batch_command([target_without_agents], 'echo hello').first
      expect(result.error_hash).to include(missing_agent_error('shell'))
    end

    it 'fails a script' do
      with_tempfile_containing('script', "#!/bin/sh\necho hello", '.sh') do |file|
        result = runner.batch_script([target_without_agents], file.path, []).first
        expect(result.error_hash).to include(missing_agent_error('shell'))
      end
    end

    it 'fails a task through the shell agent' do
      with_task_containing('tasks_test', "#!/bin/sh\necho hello", 'stdin', '.sh') do |task|
        result = runner.batch_task([target_without_agents], task, {}).first
        expect(result.error_hash).to include(missing_agent_error('shell'))
      end
    end

    it 'fails a task through the bolt_tasks agent' do
      set_config(target_without_agents, 'task-agent' => 'bolt_tasks')
      with_task_containing('tasks_test', "#!/bin/sh\necho hello", 'stdin', '.sh') do |task|
        result = runner.batch_task([target_without_agents], task, {}).first
        expect(result.error_hash).to include(missing_agent_error('bolt_tasks'))
      end
    end

    it 'fails an upload' do
      with_tempfile_containing('upload', 'content') do |file|
        result = runner.batch_upload([target_without_agents], file.path, '/tmp/choria-upload').first
        expect(result.error_hash).to include(missing_agent_error('file_transfer'))
      end
    end

    it 'fails a download' do
      Dir.mktmpdir do |destination|
        result = runner.batch_download([target_without_agents], '/etc/hostname', destination).first
        expect(result.error_hash).to include(missing_agent_error('file_transfer'))
      end
    end
  end

  context 'with a batch of targets' do
    it 'gives each target the output of its own node' do
      results = runner.batch_command([target, second_target], 'cat /etc/hostname')
      expect(results.to_h { |result| [result.target.host, result['stdout']] })
        .to eq('choria_node1' => "choria_node1\n", 'choria_node2' => "choria_node2\n")
    end

    it 'runs a command on every node through the executor' do
      results = Bolt::Executor.new.run_command([target, second_target], 'cat /etc/hostname')
      expect(results.to_h { |result| [result.target.host, result['stdout']] })
        .to eq('choria_node1' => "choria_node1\n", 'choria_node2' => "choria_node2\n")
    end

    it 'runs a task on every node' do
      contents = %(#!/bin/sh\nprintf '{"host":"%s"}' "$(cat /etc/hostname)")
      with_task_containing('tasks_test', contents, 'stdin', '.sh') do |task|
        results = runner.batch_task([target, second_target], task, {})
        expect(results.to_h { |result| [result.target.host, result['host']] })
          .to eq('choria_node1' => 'choria_node1', 'choria_node2' => 'choria_node2')
      end
    end

    it 'fails only the node without the agent and reports an event for each target' do
      events = []
      results = runner.batch_command([target, target_without_agents], 'echo hello') { |event| events << event }

      successes, failures = results.partition(&:ok?)
      expect(successes.map(&:target)).to eq([target])
      expect(successes.first['stdout']).to eq("hello\n")
      expect(failures.map(&:target)).to eq([target_without_agents])
      expect(failures.first.error_hash).to include(missing_agent_error('shell'))
      expect(events.filter_map { |event| event[:target] if event[:type] == :node_start })
        .to contain_exactly(target, target_without_agents)
      expect(events.filter_map { |event| event[:result] if event[:type] == :node_result }).to match_array(results)
    end

    it 'fails only the node that does not answer discovery' do
      results = runner.batch_command([target, missing_target], 'echo hello')

      successes, failures = results.partition(&:ok?)
      expect(successes.map(&:target)).to eq([target])
      expect(failures.map(&:target)).to eq([missing_target])
      expect(failures.first.error_hash).to include(
        'kind' => 'bolt/choria-no-response',
        'msg' => 'No response from choria://choria_missing for rpcutil.agent_inventory'
      )
    end
  end

  context 'batch_connected?' do
    it 'is true when every node answers' do
      expect(runner.batch_connected?([target, target_without_agents])).to eq(true)
    end

    it 'is false when a node does not answer' do
      expect(runner.batch_connected?([target, missing_target])).to eq(false)
    end
  end

  context 'tmpdir cleanup' do
    let(:tmpdir_pattern) { %r{\A/tmp/bolt-choria-\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z} }

    it 'removes the directory a script was uploaded to' do
      with_tempfile_containing('script', os_context[:identity_script], '.sh') do |file|
        result = runner.batch_script([target], file.path, []).first
        expect(result).to be_ok
        script_dir = File.dirname(result['stdout'].chomp)
        expect(script_dir).to match(tmpdir_pattern)
        expect(runner.run_command(target, "test -e #{script_dir}")['exit_code']).to eq(1)
      end
    end

    it 'keeps the directory a script was uploaded to, with mode 700, when cleanup is off' do
      set_config(target, 'cleanup' => false)
      with_tempfile_containing('script', os_context[:identity_script], '.sh') do |file|
        result = runner.batch_script([target], file.path, []).first
        expect(result).to be_ok
        script_dir = File.dirname(result['stdout'].chomp)
        expect(script_dir).to match(tmpdir_pattern)
        expect(runner.run_command(target, "stat -c %a #{script_dir}")['stdout']).to eq("700\n")
        runner.run_command(target, "rm -rf #{script_dir}")
      end
    end

    it 'removes the directory a task was uploaded to' do
      with_task_containing('tasks_test', os_context[:identity_script], 'environment', '.sh') do |task|
        result = runner.batch_task([target], task, {}).first
        expect(result).to be_ok
        task_dir = File.dirname(result.message.chomp)
        expect(task_dir).to match(tmpdir_pattern)
        expect(runner.run_command(target, "test -e #{task_dir}")['exit_code']).to eq(1)
      end
    end
  end

  context 'with a command that runs past command-timeout' do
    it 'fails the command and keeps it from completing' do
      set_config(target, 'command-timeout' => 2)
      marker = "/tmp/choria-timeout-#{SecureRandom.hex(4)}"

      result = runner.batch_command([target], "sleep 10; touch #{marker}").first
      expect(result.error_hash).to include('kind' => 'bolt/choria-command-timeout',
                                           'msg' => 'Command timed out after 2 seconds on choria://choria_node1')
      # The command started at least 2 seconds ago, so one that is still running creates the marker within 8 seconds
      sleep(10)
      expect(runner.run_command(target, "test -e #{marker}")['exit_code']).to eq(1)
    end
  end

  context 'with the file_transfer agent' do
    let(:remote_dir) { "/tmp/choria-transfer-#{SecureRandom.hex(4)}" }

    before { runner.batch_command([target, second_target], "mkdir #{remote_dir}") }
    after { runner.batch_command([target, second_target], "rm -rf #{remote_dir}") }

    it 'uploads a file of several messages to every node with its content and mode and no temporary file' do
      Dir.mktmpdir do |dir|
        source = File.join(dir, 'random.bin')
        File.binwrite(source, Random.new(1).bytes(3_000_000))
        File.chmod(0o640, source)
        destination = File.join(remote_dir, 'random.bin')

        expect(runner.batch_upload([target, second_target], source, destination)).to all(be_ok)
        [target, second_target].each do |node|
          listing = runner.run_command(node, "sha256sum #{destination}; stat -c %a #{destination}; ls -A #{remote_dir}")
          expect(listing['stdout']).to eq("#{Digest::SHA256.file(source).hexdigest}  #{destination}\n640\nrandom.bin\n")
        end
      end
    end

    it 'downloads a file of several messages from every node with its content' do
      source = File.join(remote_dir, 'random.bin')
      expect(runner.batch_command([target, second_target], "head -c 3000000 /dev/urandom > #{source}")).to all(be_ok)

      Dir.mktmpdir do |destination|
        results = runner.batch_download([target, second_target], source, destination)

        expect(results).to all(be_ok)
        expect(results.map(&:target)).to contain_exactly(target, second_target)
        results.each do |result|
          checksum = runner.run_command(result.target, "sha256sum #{source}")
          expect(checksum).to be_ok
          expect(File.size(result['path'])).to eq(3_000_000)
          expect(Digest::SHA256.file(result['path']).hexdigest).to eq(checksum['stdout'].split.first)
        end
      end
    end

    it 'fails a node whose destination directory does not exist and leaves nothing there' do
      with_tempfile_containing('upload', 'content') do |file|
        result = runner.batch_upload([target], file.path, File.join(remote_dir, 'missing', 'file')).first
        expect(result.error_hash).to include('kind' => 'bolt/choria-file-transfer-failed',
                                             'msg' => %r{Errno::ENOENT.*#{Regexp.escape(remote_dir)}/missing/})
      end
      listing = runner.run_command(target, "ls -A #{remote_dir}")
      expect(listing).to be_ok
      expect(listing['stdout']).to eq('')
    end

    it 'fails a node that does not have the file to download and writes nothing' do
      source = File.join(remote_dir, 'missing')
      Dir.mktmpdir do |destination|
        result = runner.batch_download([target], source, destination).first
        expect(result.error_hash).to include('kind' => 'bolt/choria-file-transfer-failed',
                                             'msg' => "#{source} does not exist on choria_node1")
        expect(Dir.children(destination)).to be_empty
      end
    end

    it 'downloads the file of each node into the directory of its target with its mode' do
      source = File.join(remote_dir, 'hostname')
      expect(runner.batch_command([target, second_target], "cp /etc/hostname #{source} && chmod 640 #{source}")).to all(be_ok)

      Dir.mktmpdir do |destination|
        results = runner.batch_download([target, second_target], source, destination)

        expect(results).to all(be_ok)
        expect(results.map(&:target)).to contain_exactly(target, second_target)
        results.each do |result|
          host = result.target.host
          target_dir = File.join(destination, "choria%3A%2F%2F#{host}")
          expect(result.message).to eq("Downloaded '#{host}:#{source}' to '#{target_dir}'")
          expect([result.action, result.object]).to eq(['download', source])
          expect(result['path']).to eq(File.join(target_dir, 'hostname'))
          expect(Dir.children(target_dir)).to eq(['hostname'])
          expect(File.read(result['path'])).to eq("#{host}\n")
          expect(File.stat(result['path']).mode & 0o777).to eq(0o640 & ~File.umask)
        end
      end
    end

    it 'downloads the directory of each node into the directory of its target' do
      tree = File.join(remote_dir, 'tree')
      setup = "mkdir -p #{tree}/sub && cp /etc/hostname #{tree}/top.txt && echo inner > #{tree}/sub/inner.txt"
      expect(runner.batch_command([target, second_target], setup)).to all(be_ok)

      Dir.mktmpdir do |destination|
        results = runner.batch_download([target, second_target], tree, destination)

        expect(results).to all(be_ok)
        expect(results.map(&:target)).to contain_exactly(target, second_target)
        results.each do |result|
          host = result.target.host
          target_dir = File.join(destination, "choria%3A%2F%2F#{host}")
          expect(result.message).to eq("Downloaded '#{host}:#{tree}' to '#{target_dir}'")
          expect(result['path']).to eq(File.join(target_dir, 'tree'))
          expect(Dir.children(result['path'])).to contain_exactly('top.txt', 'sub')
          expect(Dir.children(File.join(result['path'], 'sub'))).to eq(['inner.txt'])
          expect(File.read(File.join(result['path'], 'top.txt'))).to eq("#{host}\n")
          expect(File.read(File.join(result['path'], 'sub', 'inner.txt'))).to eq("inner\n")
        end
      end
    end
  end

  context 'with the bolt_tasks agent and the OpenVox server' do
    include BoltSpec::PAL

    let(:pal) { make_pal }

    before do
      # The first download waits for the server to load its environment
      bolt_tasks = { 'task-agent' => 'bolt_tasks', 'rpc-timeout' => 60 }
      set_config(target, bolt_tasks)
      set_config(second_target, bolt_tasks)
    end

    it 'runs a task that every node downloads from the server, with its parameters in the environment' do
      results = runner.batch_task([target, second_target], pal.get_task('sample::echo'), { 'message' => 'hello' })

      expect(results.to_h { |result| [result.target.host, result.message.chomp] })
        .to eq('choria_node1' => 'choria_node1 got passed the message: hello',
               'choria_node2' => 'choria_node2 got passed the message: hello')
    end

    it 'passes the parameters of a task on stdin' do
      result = runner.batch_task([target], pal.get_task('sample::stdin'), { 'message' => 'hello' }).first

      expect(result.value).to eq('message' => 'hello')
    end

    it 'gives a task the files its metadata lists, from its own module and from others' do
      result = runner.batch_task([target], pal.get_task('shareable'), {}).first

      files = result.message.split("\n").map(&:strip).sort
      expect(files.count).to eq(4)
      expect(files[0]).to match(%r{^174 .*/shareable/tasks/unknown_file.json$})
      expect(files[1]).to match(%r{^236 .*/shareable/tasks/list.sh$})
      expect(files[2]).to match(%r{^398 .*/results/lib/puppet/functions/results/make_result.rb$})
      expect(files[3]).to match(%r{^43 .*/error/tasks/fail.sh$})
    end

    it 'reports a task that exits non-zero with its output and the error the other transports report' do
      result = runner.batch_task([target], pal.get_task('error::fail'), {}).first

      expect(result['_output']).to eq("failing\n")
      expect(result.error_hash).to include('kind' => 'puppetlabs.tasks/task-error', 'msg' => 'The task failed with exit code 1',
                                           'details' => { 'exit_code' => 1 })
    end

    it 'fails a task that the server does not have' do
      with_task_containing('tasks_test', "#!/bin/sh\necho hello", 'stdin', '.sh') do |task|
        result = runner.batch_task([target], task, {}).first

        expect(result.error_hash).to include(
          'kind' => 'bolt/choria-rpc-error',
          'msg' => %r{\Abolt_tasks\.download on choria://choria_node1 returned RPC error: Could not download task file: .*404.*\(code 5\)\z}m
        )
      end
    end
  end
end
