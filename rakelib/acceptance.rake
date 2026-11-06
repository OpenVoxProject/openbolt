# frozen_string_literal: true

# Starts and stops the Linux test containers from spec/docker-compose.yml and
# runs the test groups that need them. CI brings the containers up with
# acceptance:up in its Linux jobs. The Windows jobs configure the runner itself
# and don't use these tasks. acceptance:local runs the local transport tests
# inside a Linux container that has the runner user the sudo examples need.
# The acceptance:choria tasks manage the Choria broker and nodes from
# spec/docker-compose.choria.yml.

# Signs a certificate for one Choria identity with the fixture CA, unless it
# exists already. Server and client usage, since the broker serves TLS and the
# nodes and the host connect to it.
def choria_certificate(dir, common_name, alt_names, ca_dir)
  cert = File.join(dir, 'cert.pem')
  return if File.exist?(cert)

  mkdir_p dir
  key = File.join(dir, 'key.pem')
  request = File.join(dir, 'request.pem')
  extensions = File.join(dir, 'extensions.cnf')
  File.write(extensions, <<~EXTENSIONS)
    basicConstraints = CA:FALSE
    keyUsage = digitalSignature, keyEncipherment
    extendedKeyUsage = serverAuth, clientAuth
    subjectAltName = #{alt_names.join(', ')}
  EXTENSIONS
  sh 'openssl', 'req', '-new', '-sha256', '-nodes', '-newkey', 'rsa:2048',
     '-keyout', key, '-out', request, '-subj', "/CN=#{common_name}"
  sh 'openssl', 'x509', '-req', '-in', request, '-out', cert, '-days', '365', '-sha256',
     '-CA', File.join(ca_dir, 'ca.pem'), '-CAkey', File.join(ca_dir, 'ca_key.pem'), '-passin', 'pass:bolt',
     '-CAcreateserial', '-CAserial', File.join(File.dirname(dir), 'ca.srl'), '-extfile', extensions
  rm_f [request, extensions]
end

namespace :acceptance do
  compose_file = File.expand_path('../spec/docker-compose.yml', __dir__)
  runner_compose_file = File.expand_path('../spec/docker-compose.runner.yml', __dir__)
  ssh_key = File.expand_path('../spec/fixtures/keys/id_rsa', __dir__)
  fixture_ssl_dir = File.expand_path('../spec/fixtures/ssl', __dir__)
  choria_dir = File.expand_path('../spec/fixtures/choria', __dir__)
  choria_compose = ['docker', 'compose', '-f', File.expand_path('../spec/docker-compose.choria.yml', __dir__)]
  # The broker also answers to the names the nodes and the host connect with
  choria_identities = {
    'choria_broker' => %w[DNS:choria_broker DNS:localhost IP:127.0.0.1],
    'choria_node1' => %w[DNS:choria_node1],
    'choria_node2' => %w[DNS:choria_node2],
    'choria_node3' => %w[DNS:choria_node3],
    'bolt.mcollective' => %w[DNS:bolt.mcollective]
  }

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

  namespace :local do
    desc 'Build and start the runner container and install the gems in it'
    task :up do
      sh 'docker', 'compose', '-f', runner_compose_file, 'up', '-d', '--build', '--wait'
      sh 'docker', 'compose', '-f', runner_compose_file, 'exec', 'runner', 'bundle', 'install'
    end

    desc 'Stop and remove the runner container and its gems volume'
    task :down do
      sh 'docker', 'compose', '-f', runner_compose_file, 'down', '--volumes'
    end
  end

  desc 'Start the runner container and run the local transport tests, sudo ones included, in it'
  task local: 'local:up' do
    compose_exec = ['docker', 'compose', '-f', runner_compose_file, 'exec']
    compose_exec += ['-e', 'SPEC'] if ENV['SPEC']
    sh(*compose_exec, 'runner', 'bundle', 'exec', 'rake', 'ci:local_transport:linux')
  end

  namespace :choria do
    desc 'Install the file_transfer client library, sign the certificates and start the Choria containers'
    task :up do
      # The transport loads the client library from the agent module, installed here from the Forge
      sh 'bundle', 'exec', 'puppet', 'module', 'install', 'overlookinfra-mcollective_agent_file_transfer',
         '--target-dir', File.join(choria_dir, 'modules'), '--ignore-dependencies', '--force'
      choria_identities.each do |identity, alt_names|
        choria_certificate(File.join(choria_dir, 'ssl', identity), identity, alt_names, fixture_ssl_dir)
      end
      sh(*choria_compose, 'up', '-d', '--build', '--wait')
    end

    desc 'Stop and remove the Choria containers with their network and volumes, the certificates and the installed module'
    task :down do
      sh(*choria_compose, 'down', '--volumes')
      rm_rf [File.join(choria_dir, 'ssl'), File.join(choria_dir, 'modules')]
    end

    desc 'Print the logs of the Choria containers'
    task :logs do
      sh(*choria_compose, 'logs', '--no-color')
    end
  end
end
