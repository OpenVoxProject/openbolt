require 'rspec/core'
SPEC_DIRECTORY = File.dirname(__FILE__)

describe 'puppet-bolt container' do
  include Pupperware::SpecHelpers

  before(:all) do
    @image = ENV['PUPPET_TEST_DOCKER_IMAGE']
    if @image.nil?
      error_message = <<-MSG
* * * * *
  PUPPET_TEST_DOCKER_IMAGE environment variable must be set so we
  know which image to test against!
* * * * *
      MSG
      fail error_message
    end
  end

  it 'should run the image' do
    result = run_command("docker run --detach #{@image}")
    container = result[:stdout].chomp
    wait_on_container_exit(container)
    expect(get_container_exit_code(container)).to eq(0)
    emit_log(container)
    teardown_container(container)
  end

  it 'should run a bolt command and analytics should be disabled' do
    result = run_command("docker run -i #{@image} command run whoami -t localhost --log-level debug 2>&1")
    expect(result[:stdout]).to match(/root/)
    expect(result[:stdout]).to match(/Analytics opt-out is set, analytics will be disabled/)
  end

  it 'should support logging UTF-8 characters' do
    result = run_command("docker run -i #{@image} command run 'echo Hello! 😆' -t localhost --log-level debug 2>&1")
    expect(result[:stdout]).to match(/Hello! 😆/)
    expect(result[:stdout]).to match(/Successful on 1 target/)
  end
end
