source 'https://rubygems.org'

def vanagon_location_for(place)
  if place =~ /^(git[:@][^#]*)#(.*)/
    [{ :git => $1, :branch => $2, :require => false }]
  elsif place =~ /^file:\/\/(.*)/
    ['>= 0', { :path => File.expand_path($1), :require => false }]
  elsif place =~ /(\d+\.\d+\.\d+)/
    [$1, {:git => 'git@github.com:puppetlabs/vanagon', :tag => $1}]
  end
end

gem "beaker-hostgenerator", *vanagon_location_for(ENV['BEAKER_HOSTGENERATOR_VERSION'] || "~> 0.7")
gem "beaker-abs", *vanagon_location_for(ENV['BEAKER_ABS_VERSION'] || "~> 0.1")
gem 'vanagon', *vanagon_location_for(ENV['VANAGON_LOCATION'] || '~> 0.15.3')
gem 'packaging', *vanagon_location_for(ENV['PACKAGING_LOCATION'] || '~> 0.99')
gem 'json'
gem 'rake'
