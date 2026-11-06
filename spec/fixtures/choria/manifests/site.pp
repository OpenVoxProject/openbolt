node 'choria_broker' {
  include choria
  include choria::broker
}

node default {
  include choria
  file { '/root/.choria':
    ensure  => file,
    content => "plugin.security.provider = puppet\nplugin.security.certname = ${trusted['certname']}\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
  }
}
