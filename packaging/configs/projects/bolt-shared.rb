proj.license "See components"
proj.vendor "Puppet, Inc.  <info@puppet.com>"
proj.homepage "https://www.puppet.com"
proj.identifier "com.puppetlabs"

# Building native gems on Windows has some issues right now.
# Include for non-Windows platforms only.
unless platform.is_windows?
  proj.component 'rubygem-bcrypt_pbkdf'
  proj.component 'rubygem-ed25519'
end

proj.component 'rubygem-public_suffix'
proj.component 'rubygem-addressable'
proj.component 'rubygem-concurrent-ruby'
proj.component 'rubygem-net-scp'
proj.component 'rubygem-orchestrator_client'
proj.component 'rubygem-unicode-display_width'
proj.component 'rubygem-terminal-table'
proj.component 'rubygem-gssapi'
proj.component 'rubygem-httpclient'
proj.component 'rubygem-rubyntlm'
proj.component 'rubygem-little-plugger'
proj.component 'rubygem-logging'
proj.component 'rubygem-nori'
proj.component 'rubygem-builder'
proj.component 'rubygem-gyoku'
proj.component 'rubygem-erubis'
proj.component 'rubygem-winrm'
proj.component 'rubygem-rubyzip'
proj.component 'rubygem-winrm-fs'
proj.component 'rubygem-CFPropertyList'
proj.component 'rubygem-colored'
proj.component 'rubygem-cri'
proj.component 'rubygem-multipart-post'
proj.component 'rubygem-faraday'
proj.component 'rubygem-faraday_middleware'
proj.component 'rubygem-puppet_forge'
proj.component 'rubygem-log4r'
proj.component 'rubygem-r10k'
proj.component 'rubygem-facter'
proj.component 'rubygem-hiera'
proj.component 'rubygem-hocon'
proj.component 'rubygem-puppet-resource_api'
proj.component 'rubygem-puppet'
proj.component 'rubygem-excon'
proj.component 'rubygem-docker-api'
proj.component 'rubygem-ruby_smb'
proj.component 'rubygem-bindata'
proj.component 'rubygem-windows_error'
