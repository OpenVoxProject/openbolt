# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'fileutils'
require 'json'
require 'minitar'
require 'open3'
require 'rbconfig'
require 'stringio'
require 'tmpdir'
require 'zlib'

# Runs the helpers in libexec as a target runs them, in a Ruby of their own.
describe 'apply helpers', apply: true do
  let(:workdir) { Dir.mktmpdir }
  let(:fact_value) { 'unpacked from the plugins tarball' }
  let(:encoded_plugins) { Base64.encode64(plugin_tarball) }
  let(:queried_file) { File.join(workdir, 'queried.txt').tap { |path| File.write(path, 'queried') } }
  let(:query_arguments) { { 'resources' => ["File[#{queried_file}]"] } }
  let(:apply_arguments) do
    catalog = {
      'name' => 'apply-helpers-spec',
      'version' => 1,
      'environment' => 'production',
      'resources' => [
        { 'type' => 'Notify', 'title' => 'example', 'exported' => false, 'parameters' => { 'message' => 'applied' } }
      ],
      'edges' => [],
      'classes' => []
    }
    { 'catalog' => catalog, 'apply_settings' => {}, 'bolt_builtin_content' => [] }
  end

  after(:each) { FileUtils.remove_entry(workdir) }

  # Returns a gzip tar that contains a module named example, packed the way Bolt::Applicator#build_plugin_tarball packs it
  def plugin_tarball
    fact_source = "Facter.add(:example_fact) { setcode { '#{fact_value}' } }\n"
    gzipped = StringIO.new
    output = Minitar::Output.new(Zlib::GzipWriter.new(gzipped))
    output.tar.add_file_simple('example/lib/facter/example_fact.rb',
                               data: fact_source, size: fact_source.bytesize, mode: 0o644, mtime: Time.now)
    output.close
    gzipped.string
  end

  # Writes the arguments to a directory of their own and returns the file path
  def write_arguments(arguments)
    path = File.join(workdir, 'arguments', 'arguments.json')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, arguments.to_json)
    path
  end

  def write_plugins(directory)
    path = File.join(directory, 'plugins.tar.gz')
    FileUtils.mkdir_p(directory)
    File.binwrite(path, plugin_tarball)
    path
  end

  def write_arguments_beside_plugins(arguments)
    arguments_file = write_arguments(arguments.merge('plugins_file' => 'plugins.tar.gz'))
    write_plugins(File.dirname(arguments_file))
    arguments_file
  end

  # Runs the helper in workdir and returns stdout, stderr and the exit status
  def run_helper(helper, *argv, stdin: '')
    helper_path = File.expand_path("../../libexec/#{helper}", __dir__)
    Open3.capture3(RbConfig.ruby, helper_path, *argv, stdin_data: stdin, chdir: workdir)
  end

  def expect_custom_fact(out, err, status)
    expect(status.exitstatus).to eq(0), err
    expect(JSON.parse(out)).to include('example_fact' => fact_value)
  end

  def expect_queried_file(out, err, status)
    expect(status.exitstatus).to eq(0), err
    expect(JSON.parse(out)['resources']).to contain_exactly(include('type' => 'File', 'title' => queried_file))
  end

  def expect_notify_applied(out, err, status)
    expect(status.exitstatus).to eq(0), err
    report = JSON.parse(out)
    expect(report['status']).not_to eq('failed')
    expect(report['resource_statuses']).to include('Notify[example]' => include('changed' => true))
  end

  describe 'custom_facts.rb' do
    it 'returns the custom fact from base64 plugins on stdin' do
      out, err, status = run_helper('custom_facts.rb', stdin: { 'plugins' => encoded_plugins }.to_json)

      expect_custom_fact(out, err, status)
    end

    it 'returns the custom fact from a plugins_file beside the arguments file named by the first argument' do
      out, err, status = run_helper('custom_facts.rb', write_arguments_beside_plugins({}))

      expect_custom_fact(out, err, status)
    end

    it 'returns the custom fact from a plugins_file relative to the current directory with arguments on stdin' do
      write_plugins(workdir)
      out, err, status = run_helper('custom_facts.rb', stdin: { 'plugins_file' => 'plugins.tar.gz' }.to_json)

      expect_custom_fact(out, err, status)
    end

    it 'returns the custom fact from an absolute plugins_file outside the directory of the arguments file' do
      plugins_file = write_plugins(File.join(workdir, 'plugins'))
      out, err, status = run_helper('custom_facts.rb', write_arguments('plugins_file' => plugins_file))

      expect_custom_fact(out, err, status)
    end

    it 'exits non-zero and names the plugins_file when it does not exist' do
      _out, err, status = run_helper('custom_facts.rb', write_arguments('plugins_file' => 'missing.tar.gz'))

      expect(status.exitstatus).not_to eq(0)
      expect(err).to include('missing.tar.gz')
    end
  end

  describe 'query_resources.rb' do
    it 'returns the queried file resource with base64 plugins on stdin' do
      out, err, status = run_helper('query_resources.rb', stdin: query_arguments.merge('plugins' => encoded_plugins).to_json)

      expect_queried_file(out, err, status)
    end

    it 'returns the queried file resource with a plugins_file beside the arguments file named by the first argument' do
      out, err, status = run_helper('query_resources.rb', write_arguments_beside_plugins(query_arguments))

      expect_queried_file(out, err, status)
    end
  end

  describe 'apply_catalog.rb' do
    it 'applies the notify and exits 0 with base64 plugins on stdin' do
      out, err, status = run_helper('apply_catalog.rb', stdin: apply_arguments.merge('plugins' => encoded_plugins).to_json)

      expect_notify_applied(out, err, status)
    end

    it 'applies the notify and exits 0 with base64 plugins in the arguments file named by the first argument' do
      arguments_file = write_arguments(apply_arguments.merge('plugins' => encoded_plugins))
      out, err, status = run_helper('apply_catalog.rb', arguments_file)

      expect_notify_applied(out, err, status)
    end

    it 'applies the notify and exits 0 with a plugins_file beside the arguments file named by the first argument' do
      out, err, status = run_helper('apply_catalog.rb', write_arguments_beside_plugins(apply_arguments))

      expect_notify_applied(out, err, status)
    end

    it 'leaves the arguments file and the plugins file in place' do
      arguments_file = write_arguments_beside_plugins(apply_arguments)
      _out, err, status = run_helper('apply_catalog.rb', arguments_file)

      expect(status.exitstatus).to eq(0), err
      expect(File.exist?(arguments_file)).to be(true)
      expect(File.exist?(File.join(File.dirname(arguments_file), 'plugins.tar.gz'))).to be(true)
    end
  end
end
