#!/bin/sh
# The image only enables its HTTPS listener when it fetches certificates from
# an OpenVox Server. The test stack mounts the fixture certificates at the paths
# the commented ssl-* lines in jetty.ini already name, so just uncomment them.
set -e

sed -i '/^# ssl-/s/^# //g' /etc/puppetlabs/puppetdb/conf.d/jetty.ini
