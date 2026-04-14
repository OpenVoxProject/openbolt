# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/choria'
require 'bolt_spec/sensitive'

describe 'Bolt::Transport::Choria bolt_tasks' do
  include_context 'choria transport'
  include_context 'choria task'
  include BoltSpec::Sensitive

  describe '#unwrap_bolt_tasks_stdout' do
    before(:each) do
      transport.configure_client(target)
    end

    it 'passes through JSON hash stdout unchanged' do
      raw = '{"_output":"hello world"}'
      expect(transport.unwrap_bolt_tasks_stdout(raw)).to eq(raw)
    end

    it 'passes through non-JSON content unchanged' do
      expect(transport.unwrap_bolt_tasks_stdout('plain text')).to eq('plain text')
    end

    it 'unwraps double-encoded wrapper error' do
      inner = '{"_error":{"kind":"choria.tasks/wrapper-error","msg":"wrapper failed"}}'
      double_encoded = inner.to_json
      expect(transport.unwrap_bolt_tasks_stdout(double_encoded)).to eq(inner)
    end

    it 'returns nil unchanged' do
      expect(transport.unwrap_bolt_tasks_stdout(nil)).to be_nil
    end

    it 'returns empty string unchanged' do
      expect(transport.unwrap_bolt_tasks_stdout('')).to eq('')
    end

    it 'returns integer unchanged' do
      expect(transport.unwrap_bolt_tasks_stdout(42)).to eq(42)
    end
  end

  describe '#task_file_spec' do
    let(:file_content) { '#!/bin/bash' }
    let(:file_path) { '/path/to/file' }
    let(:expected_sha256) { Digest::SHA256.hexdigest(file_content) }
    let(:expected_size) { file_content.bytesize }

    before(:each) do
      transport.configure_client(target)
      mock_digest = instance_double(Digest::SHA256, hexdigest: expected_sha256)
      allow(Digest::SHA256).to receive(:file).and_call_original
      allow(Digest::SHA256).to receive(:file).with(file_path).and_return(mock_digest)
      allow(File).to receive(:size).and_call_original
      allow(File).to receive(:size).with(file_path).and_return(expected_size)
    end

    def expect_file_spec(spec, filename:, uri_path:, environment: 'production')
      expect(spec['filename']).to eq(filename)
      expect(spec['uri']['path']).to eq(uri_path)
      expect(spec['uri']['params']).to eq({ 'environment' => environment })
      expect(spec['sha256']).to eq(expected_sha256)
      expect(spec['size_bytes']).to eq(expected_size)
    end

    it 'builds a file spec for a simple task file' do
      spec = transport.task_file_spec(
        { 'name' => 'mytask.sh', 'path' => file_path },
        'mymod', 'production'
      )

      expect_file_spec(spec,
                       filename: 'mytask.sh',
                       uri_path: '/puppet/v3/file_content/tasks/mymod/mytask.sh')
    end

    it 'uses the modules mount for files/ directory dependencies' do
      spec = transport.task_file_spec(
        { 'name' => 'ruby_task_support/files/task_support.rb', 'path' => file_path },
        'mymod', 'production'
      )

      expect_file_spec(spec,
                       filename: 'ruby_task_support/files/task_support.rb',
                       uri_path: '/puppet/v3/file_content/modules/ruby_task_support/task_support.rb')
    end

    it 'uses the plugins mount for lib/ directory dependencies' do
      spec = transport.task_file_spec(
        { 'name' => 'mymod/lib/puppet/util/support.rb', 'path' => file_path },
        'mymod', 'production'
      )

      expect_file_spec(spec,
                       filename: 'mymod/lib/puppet/util/support.rb',
                       uri_path: '/puppet/v3/file_content/plugins/mymod/puppet/util/support.rb')
    end

    it 'uses the tasks mount for other subdirectories' do
      spec = transport.task_file_spec(
        { 'name' => 'mymod/tasks/thing.sh', 'path' => file_path },
        'mymod', 'production'
      )

      expect_file_spec(spec,
                       filename: 'mymod/tasks/thing.sh',
                       uri_path: '/puppet/v3/file_content/tasks/mymod/thing.sh')
    end

    it 'uses a custom environment in the URI params' do
      spec = transport.task_file_spec(
        { 'name' => 'mytask.sh', 'path' => file_path },
        'mymod', 'staging'
      )

      expect_file_spec(spec,
                       filename: 'mytask.sh',
                       uri_path: '/puppet/v3/file_content/tasks/mymod/mytask.sh',
                       environment: 'staging')
    end
  end

  describe '#download_and_start_task' do
    include_context 'choria task file stubs'

    before(:each) do
      stub_agents([target, target2], %w[rpcutil bolt_tasks])
      allow(mock_rpc_client).to receive_messages(
        download: [make_download_result(target), make_download_result(target2)],
        run_no_wait: [make_task_run_result(target), make_task_run_result(target2)],
        task_status: [make_task_status_result(target, stdout: '{"result":"success"}'),
                      make_task_status_result(target2, stdout: '{"result":"success"}')]
      )
    end

    it 'sends the correct download arguments' do
      expect(mock_rpc_client).to receive(:download).with(hash_including(
                                                           task: task_name,
                                                           environment: 'production'
                                                         ))

      transport.batch_task([target], task, { 'param1' => 'value1' })
    end

    it 'sends the correct run_no_wait arguments' do
      expect(mock_rpc_client).to receive(:run_no_wait).with(hash_including(
                                                              task: task_name,
                                                              input_method: 'both'
                                                            ))

      transport.batch_task([target], task, { 'param1' => 'value1' })
    end

    it 'unwraps Sensitive values in task arguments' do
      expect(mock_rpc_client).to receive(:run_no_wait).with(
        hash_including(input: include('"s3cret"'))
      ).and_return([make_task_run_result(target)])

      transport.batch_task([target], task, { 'password' => make_sensitive('s3cret') })
    end

    it 'uses configured puppet-environment for file URIs' do
      inventory.set_config(target, %w[choria puppet-environment], 'staging')

      expect(mock_rpc_client).to receive(:download).with(hash_including(
                                                           environment: 'staging'
                                                         )).and_return([make_download_result(target)])

      transport.batch_task([target], task, {})
    end

    it 'builds correct file spec URIs in the download request' do
      expect(mock_rpc_client).to receive(:download) do |args|
        files = JSON.parse(args[:files])
        expect(files.length).to eq(1)
        expect(files.first['filename']).to eq('mytask.sh')
        expect(files.first['uri']['path']).to eq('/puppet/v3/file_content/tasks/mymod/mytask.sh')
        expect(files.first).to have_key('sha256')
        expect(files.first).to have_key('size_bytes')
        [make_download_result(target)]
      end

      transport.batch_task([target], task, {})
    end

    it 'uses bare filename for primary executable even when name has slashes' do
      slashed_task = Bolt::Task.new(
        task_name,
        { 'input_method' => 'both' },
        [{ 'name' => 'mymod/tasks/mytask.sh', 'path' => task_executable }]
      )

      expect(mock_rpc_client).to receive(:download) do |args|
        files = JSON.parse(args[:files])
        expect(files.first['filename']).to eq('mytask.sh')
        expect(files.first['uri']['path']).to eq('/puppet/v3/file_content/tasks/mymod/mytask.sh')
        [make_download_result(target)]
      end

      transport.batch_task([target], slashed_task, {})
    end

    it 'includes dependency files with correct mounts in the download request' do
      dep_path1 = '/path/to/ruby_task_support/files/task_support.rb'
      dep_path2 = '/path/to/mymod/lib/puppet/util/support.rb'
      multi_file_task = Bolt::Task.new(
        task_name,
        { 'input_method' => 'both',
          'files' => ['ruby_task_support/files/task_support.rb', 'mymod/lib/puppet/util/support.rb'] },
        [{ 'name' => 'mytask.sh', 'path' => task_executable },
         { 'name' => 'ruby_task_support/files/task_support.rb', 'path' => dep_path1 },
         { 'name' => 'mymod/lib/puppet/util/support.rb', 'path' => dep_path2 }]
      )

      mock_digest = instance_double(Digest::SHA256, hexdigest: 'abc123')
      allow(Digest::SHA256).to receive(:file).with(dep_path1).and_return(mock_digest)
      allow(Digest::SHA256).to receive(:file).with(dep_path2).and_return(mock_digest)
      allow(File).to receive(:size).with(dep_path1).and_return(8)
      allow(File).to receive(:size).with(dep_path2).and_return(8)

      expect(mock_rpc_client).to receive(:download) do |args|
        files = JSON.parse(args[:files])
        expect(files.length).to eq(3)
        expect(files[0]['uri']['path']).to eq('/puppet/v3/file_content/tasks/mymod/mytask.sh')
        expect(files[1]['uri']['path']).to eq('/puppet/v3/file_content/modules/ruby_task_support/task_support.rb')
        expect(files[2]['uri']['path']).to eq('/puppet/v3/file_content/plugins/mymod/puppet/util/support.rb')
        [make_download_result(target)]
      end

      transport.batch_task([target], multi_file_task, {})
    end

    describe 'error handling' do
      it 'returns error when download fails with non-zero statuscode' do
        failed_dl = make_rpc_result(sender: target, statuscode: 5, statusmsg: 'Download error')
        allow(mock_rpc_client).to receive(:download).and_return([failed_dl])

        result = transport.batch_task([target], task, {}).first
        expect(result.ok?).to be false
        expect(result.error_hash['msg']).to match(/bolt_tasks\.download on .+ returned RPC error: Download error/)
      end

      it 'catches download failure reported via statuscode 1 (reply.fail!)' do
        # The bolt_tasks agent uses reply.fail! for download failures, which
        # sets statuscode 1. rpc_request routes statuscode 1 to :responded,
        # so download_and_start_task has special logic to check rpc_statuscodes
        # and move statuscode-1 responses to the error bucket.
        dl_result = make_rpc_result(
          sender: target, statuscode: 1,
          statusmsg: 'Could not download task files from puppet server',
          data: { downloads: 0 }
        )
        allow(mock_rpc_client).to receive(:download).and_return([dl_result])

        result = transport.batch_task([target], task, {}).first
        expect(result.ok?).to be false
        expect(result.error_hash['msg']).to match(/failed to download task files/)
      end

      it 'returns error when download returns no response' do
        allow(mock_rpc_client).to receive(:download).and_return([])

        result = transport.batch_task([target], task, {}).first
        expect(result.ok?).to be false
        expect(result.error_hash['msg']).to match(/No response from .+ for bolt_tasks\.download/)
      end

      it 'returns error when run_no_wait returns no response' do
        allow(mock_rpc_client).to receive(:run_no_wait).and_return([])

        result = transport.batch_task([target], task, {}).first
        expect(result.ok?).to be false
        expect(result.error_hash['msg']).to match(/No response from .+ for bolt_tasks\.run_no_wait/)
      end

      it 'returns error when run_no_wait returns non-zero statuscode' do
        failed_run = make_rpc_result(sender: target, statuscode: 5, statusmsg: 'Agent rejected task')
        allow(mock_rpc_client).to receive(:run_no_wait).and_return([failed_run])

        result = transport.batch_task([target], task, {}).first
        expect(result.ok?).to be false
        expect(result.error_hash['msg']).to match(/bolt_tasks\.run_no_wait on .+ returned RPC error: Agent rejected task/)
      end

      it 'returns error when run_no_wait returns success but no task_id' do
        nil_id_result = make_rpc_result(sender: target, data: { task_id: nil })
        allow(mock_rpc_client).to receive(:run_no_wait).and_return([nil_id_result])

        result = transport.batch_task([target], task, {}).first
        expect(result.ok?).to be false
        expect(result.error_hash['msg']).to match(/succeeded but returned no task_id/)
      end

      it 'returns error results for all targets when download raises' do
        stub_agents([target, target2], %w[rpcutil bolt_tasks])
        allow(mock_rpc_client).to receive(:download).and_raise(StandardError, 'connection reset')

        results = transport.batch_task([target, target2], task, {})
        expect(results.length).to eq(2)
        results.each do |result|
          expect(result.ok?).to be false
          expect(result.error_hash['msg']).to match(/bolt_tasks\.download failed on .+: connection reset/)
        end
      end

      it 'returns error results for all targets when run_no_wait raises' do
        stub_agents([target, target2], %w[rpcutil bolt_tasks])
        allow(mock_rpc_client).to receive(:download).and_return([
                                                                  make_download_result(target), make_download_result(target2)
                                                                ])
        allow(mock_rpc_client).to receive(:run_no_wait).and_raise(StandardError, 'broker disconnected')

        results = transport.batch_task([target, target2], task, {})
        expect(results.length).to eq(2)
        results.each do |result|
          expect(result.ok?).to be false
          expect(result.error_hash['msg']).to match(/bolt_tasks\.run_no_wait failed on .+: broker disconnected/)
        end
      end

      it 'handles partial download failure across targets' do
        stub_agents([target, target2], %w[rpcutil bolt_tasks])
        dl2 = make_rpc_result(sender: target2, statuscode: 5, statusmsg: 'Puppet server unreachable')
        allow(mock_rpc_client).to receive_messages(
          download: [make_download_result(target), dl2],
          run_no_wait: [make_task_run_result(target)],
          task_status: [make_task_status_result(target)]
        )

        results = transport.batch_task([target, target2], task, {})
        expect(results.length).to eq(2)

        ok_results = results.select(&:ok?)
        error_results = results.reject(&:ok?)
        expect(ok_results.length).to eq(1)
        expect(ok_results.first.target).to eq(target)
        expect(error_results.length).to eq(1)
        expect(error_results.first.target).to eq(target2)
        expect(error_results.first.error_hash['msg']).to match(/bolt_tasks\.download on .+ returned RPC error: Puppet server unreachable/)
      end
    end
  end

  describe '#poll_task_status' do
    include_context 'choria task file stubs'

    before(:each) do
      stub_agents(target, %w[rpcutil bolt_tasks])
      allow(mock_rpc_client).to receive_messages(
        download: [make_download_result(target)],
        run_no_wait: [make_task_run_result(target)]
      )
    end

    it 'returns task output on successful completion' do
      allow(mock_rpc_client).to receive(:task_status).and_return([
                                                                   make_task_status_result(target, stdout: '{"result":"success"}')
                                                                 ])

      result = transport.batch_task([target], task, {}).first
      expect(result.ok?).to be true
      expect(result.value).to eq('result' => 'success')
    end

    it 'handles JSON hash stdout' do
      allow(mock_rpc_client).to receive(:task_status).and_return([
                                                                   make_task_status_result(target, stdout: '{"msg":"hello"}')
                                                                 ])

      result = transport.batch_task([target], task, {}).first
      expect(result.value).to eq('msg' => 'hello')
    end

    it 'handles double-encoded string stdout from wrapper errors' do
      inner_json = '{"_error":{"msg":"wrapper failed","kind":"choria/wrapper_failed","details":{}}}'
      allow(mock_rpc_client).to receive(:task_status).and_return([
                                                                   make_task_status_result(target, stdout: inner_json.to_json)
                                                                 ])

      result = transport.batch_task([target], task, {}).first
      expect(result.value).to include('_error' => a_hash_including('msg' => 'wrapper failed',
                                                                   'kind' => 'choria/wrapper_failed'))
    end

    it 'handles plain text stdout wrapped in _output' do
      allow(mock_rpc_client).to receive(:task_status).and_return([
                                                                   make_task_status_result(target, stdout: '{"_output":"hello world"}')
                                                                 ])

      result = transport.batch_task([target], task, {}).first
      expect(result.value).to eq('_output' => 'hello world')
    end

    it 'handles empty stdout' do
      allow(mock_rpc_client).to receive(:task_status).and_return([
                                                                   make_task_status_result(target, stdout: '')
                                                                 ])

      result = transport.batch_task([target], task, {}).first
      expect(result.value).to eq('_output' => '')
    end

    it 'preserves task output when agent returns statuscode 1 for failed tasks' do
      failed_status = make_rpc_result(
        sender: target,
        statuscode: 1,
        statusmsg: 'choria.tasks/task-error: The task errored with a code 1',
        data: {
          completed: true, exitcode: 1,
          stdout: '{"_output":"task failed","_error":{"kind":"choria.tasks/task-error",' \
                  '"msg":"The task errored with a code 1","details":{"exitcode":1}}}',
          stderr: 'something went wrong'
        }
      )
      allow(mock_rpc_client).to receive(:task_status).and_return([failed_status])

      result = transport.batch_task([target], task, {}).first
      expect(result.ok?).to be false
      expect(result.value).to include('_error' => a_hash_including('kind' => 'choria.tasks/task-error'))
    end

    it 'defaults nil exitcode to 1' do
      allow(mock_rpc_client).to receive(:task_status).and_return([
                                                                   make_task_status_result(target, exitcode: nil, stdout: '{"_output":"task ran"}')
                                                                 ])

      result = transport.batch_task([target], task, {}).first
      expect(result.value['_error']['details']['exit_code']).to eq(1)
    end

    it 'returns error on task timeout' do
      never_done = make_task_status_result(target, completed: false, exitcode: nil, stdout: '', stderr: '')
      allow(mock_rpc_client).to receive(:task_status).and_return([never_done])
      inventory.set_config(target, %w[choria task-timeout], 1)

      result = transport.batch_task([target], task, {}).first
      expect(result.ok?).to be false
      expect(result.error_hash['msg']).to match(/timed out/)
    end

    it 'returns error when task_status returns non-zero statuscode' do
      status_result = make_rpc_result(sender: target, statuscode: 4, statusmsg: 'Authorization denied for bolt_tasks')
      allow(mock_rpc_client).to receive(:task_status).and_return([status_result])

      result = transport.batch_task([target], task, {}).first
      expect(result.ok?).to be false
      expect(result.error_hash['kind']).to eq('bolt/choria-rpc-error')
      expect(result.error_hash['msg']).to match(/Authorization denied/)
    end

    it 'fails all targets after 3 consecutive poll RPC failures' do
      allow(mock_rpc_client).to receive(:task_status)
        .and_raise(StandardError, 'NATS connection lost')

      result = transport.batch_task([target], task, {}).first
      expect(result.ok?).to be false
      expect(result.error_hash['kind']).to eq('bolt/choria-poll-failed')
      expect(result.error_hash['msg']).to match(/failed persistently/)
    end

    it 'recovers after transient poll failures and completes successfully' do
      call_count = 0
      allow(mock_rpc_client).to receive(:task_status) do
        call_count += 1
        raise StandardError, 'transient NATS error' if call_count <= 2

        [make_task_status_result(target)]
      end

      result = transport.batch_task([target], task, {}).first
      expect(result.ok?).to be true
      expect(result.value).to eq('result' => 'ok')
    end
  end
end
