# frozen_string_literal: true

# Starts and stops the Linux test containers from spec/docker-compose.yml and
# runs the test groups that need them. CI brings the containers up with
# acceptance:up through the composite actions under .github/actions. The
# Windows jobs configure the runner itself and don't use these tasks.
namespace :acceptance do
  compose_file = File.expand_path('../spec/docker-compose.yml', __dir__)
  ssh_key = File.expand_path('../spec/fixtures/keys/id_rsa', __dir__)

  desc 'Build and start the test containers and wait until they are healthy'
  task :up do
    # Git checks the key out world readable and the OpenSSH client refuses it that way
    File.chmod(0o600, ssh_key)
    sh 'docker', 'compose', '-f', compose_file, 'up', '-d', '--build', '--wait'
  end

  desc 'Stop and remove the test containers with their network and volumes'
  task :down do
    sh 'docker', 'compose', '-f', compose_file, 'down', '--volumes'
  end

  desc 'Print the logs of the test containers'
  task :logs do
    sh 'docker', 'compose', '-f', compose_file, 'logs', '--no-color'
  end

  desc 'Start the test containers and run the SSH transport tests'
  task ssh: %w[up ci:ssh_transport]

  desc 'Start the test containers and run the Docker transport tests'
  task docker: %w[up ci:docker_transport]

  desc 'Start the test containers and run the Linux integration tests'
  task integration: %w[up ci:linux:integration]

  desc 'Start the test containers and run the Linux apply tests'
  task apply: %w[up tests:install_modules ci:apply:linux]

  desc 'Start the test containers and run the BoltSpec tests'
  task boltspec: %w[up ci:boltspec:linux]
end
