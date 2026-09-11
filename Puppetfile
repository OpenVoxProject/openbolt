# frozen_string_literal: true

forge 'https://forge.puppetlabs.com'

moduledir File.join(File.dirname(__FILE__), 'modules')

# Core modules used by 'apply'
mod 'puppetlabs-service', '4.0.0'
mod 'puppet-openvox_bootstrap', '1.4.0'
mod 'puppetlabs-facts', '1.8.0'

# Other core Puppet modules
mod 'puppetlabs-inifile', '6.5.0'
mod 'puppetlabs-apt', '11.4.0'
mod 'puppetlabs-stdlib', '10.1.0'
mod 'puppetlabs-powershell', '6.2.0'
mod 'puppetlabs-pwshlib', '2.1.1'

# Core types and providers for Puppet 6
mod 'puppetlabs-augeas_core', '2.0.1'
mod 'puppetlabs-host_core', '2.0.1'
mod 'puppetlabs-scheduled_task', '5.1.0'
mod 'puppetlabs-sshkeys_core', '3.0.2'
mod 'puppetlabs-zfs_core', '2.0.1'
mod 'puppetlabs-cron_core', '2.0.3'
mod 'puppetlabs-mount_core', '2.0.1'
mod 'puppetlabs-selinux_core', '2.0.1'
mod 'puppetlabs-yumrepo_core', '3.0.1'
mod 'puppetlabs-zone_core', '2.0.2'

# Useful additional modules
mod 'puppetlabs-package', '4.0.0'
mod 'puppetlabs-puppet_conf', '3.0.0'
mod 'puppetlabs-reboot', '6.0.0'

# Task helpers
mod 'puppetlabs-powershell_task_helper', '0.2.0'
mod 'puppetlabs-ruby_task_helper', '1.1.0'
mod 'puppetlabs-ruby_plugin_helper', '0.4.0'
mod 'puppetlabs-python_task_helper', '0.7.0'
mod 'puppetlabs-bash_task_helper', '2.3.0'

# Plugin modules
mod 'puppetlabs-aws_inventory', '0.9.0'
mod 'puppetlabs-azure_inventory', '0.6.0'
mod 'puppetlabs-gcloud_inventory', '0.4.0'
mod 'puppetlabs-http_request', '0.4.0'
mod 'puppetlabs-pkcs7', '0.2.0'
mod 'puppetlabs-secure_env_vars', '0.3.0'
mod 'puppetlabs-terraform', '0.8.0'
mod 'puppetlabs-vault', '0.5.0'
mod 'puppetlabs-yaml', '0.3.0'

# If we don't list these modules explicitly, r10k will purge them
mod 'canary', local: true
mod 'aggregate', local: true
mod 'puppetdb_fact', local: true
