# Puppet-bolt container

Puppet Bolt it available as a docker image. This document covers some possible ways to use the container.

## Building and Test

A makefile is provided for building and testing the puppet-bolt container. Execute `make build` to build the latest or `make test` to run the tests.

## Completely stand-alone

When running Bolt from the container, the `localhost` target is the container environment (not the docker host environment). The following example shows running a command against the localhost target in the container.
```
cas@cas-ThinkPad-T460p:~/working_dir/docker_bolt$ docker run puppet-bolt command run 'cat /etc/os-release' -t localhost
Started on localhost...
Finished on localhost:
  STDOUT:
    NAME="Ubuntu"
    VERSION="16.04.6 LTS (Xenial Xerus)"
    ID=ubuntu
    ID_LIKE=debian
    PRETTY_NAME="Ubuntu 16.04.6 LTS"
    VERSION_ID="16.04"
    HOME_URL="http://www.ubuntu.com/"
    SUPPORT_URL="http://help.ubuntu.com/"
    BUG_REPORT_URL="http://bugs.launchpad.net/ubuntu/"
    VERSION_CODENAME=xenial
    UBUNTU_CODENAME=xenial
Successful on 1 node: localhost
Ran on 1 node in 0.00 seconds
```
In order to pass connection information and custom module content we need to share data from the host with the container. The following sections describe some ways to accomplish sharing data with the puppet Bolt container.

## Pass Inventory as an environment variable

In the case where no custom module content is required for the Bolt action you wish to execute with the container and the only information you need is how to connect to targets you can pass inventory as an enviornment variable. The following inventory has all the information needed to connect to the example target. 

```yaml
---
nodes:
  - name: pnz2rzpxfzp95hh.delivery.puppetlabs.net
    alias: docker-example
    config:
      transport: ssh
      ssh:
        user: root
        password: secret-password
        host-key-check: false
```
The following invocation shows an example of running the built-in `facts` task against the target listed in inventory. 
```
cas@cas-ThinkPad-T460p:~/working_dir/docker_bolt$ docker run --env "BOLT_INVENTORY=$(cat Boltdir/inventory.yaml)" puppet-bolt task run facts -t docker-example
Started on pnz2rzpxfzp95hh.delivery.puppetlabs.net...
Finished on pnz2rzpxfzp95hh.delivery.puppetlabs.net:
  {
    "os": {
      "name": "CentOS",
      "release": {
        "full": "7.2",
        "major": "7",
        "minor": "2"
      },
      "family": "RedHat"
    }
  }
Successful on 1 node: pnz2rzpxfzp95hh.delivery.puppetlabs.net
Ran on 1 node in 0.55 seconds
```
## Mount Bolt project directory from host 

This section describes making a Bolt project directory (Boltdir) available to the container. The directory structure and relevant file content is listed below:
```
cas@cas-ThinkPad-T460p:~/working_dir/docker_bolt$ tree
.
└── Boltdir
    ├── bolt.yaml
    ├── inventory.yaml
    ├── keys
    │   └── id_rsa-acceptance
    └── site-modules
        └── docker_task
            └── tasks
                └── init.sh

5 directories, 4 files
```
**bolt.yaml**

Bolt configuration file
```yaml
---
log:
  console:
    level: notice
```
**inventory.yaml**

Store information about targets. Note the absolute path to the private key is the path in the container not the host.
```yaml
---
nodes:
  - name: pnz2rzpxfzp95hh.delivery.puppetlabs.net
    alias: docker-example
    config:
      transport: ssh
      ssh:
        user: root
        private-key: /Boltdir/keys/id_rsa-acceptance
        host-key-check: false
```
**init.sh**

Example shell task that echos a `message` parameter.
```bash
#!/bin/bash
echo "Message: ${PT_message}"
```
In order to execute the task with docker and provide all the information provided in the Bolt project directory it is possible to mount the Boltdir on the host with the following invocation:
```
cas@cas-ThinkPad-T460p:~/working_dir/docker_bolt$ docker run --mount type=bind,source=/home/cas/working_dir/docker_bolt/Boltdir,destination=/Boltdir puppet-bolt task run docker_task message=hi -t docker-example
Started on pnz2rzpxfzp95hh.delivery.puppetlabs.net...
Finished on pnz2rzpxfzp95hh.delivery.puppetlabs.net:
  Message: hi
  {
  }
Successful on 1 node: pnz2rzpxfzp95hh.delivery.puppetlabs.net
Ran on 1 node in 0.56 seconds
```

The `--mount` flag maps the local directory to the root directory in the container (the working directory), the container is tagged as `puppet-bolt` and the rest of the invocation are all native to Bolt. 

## Building on top of the puppet-bolt image

You can also extend the puppet-bolt image and copy in data that will always be available for that image. In order to illustrate this we can add a Dockerfile to the directory structure defined in the previous example with the following content:
```
cas@cas-ThinkPad-T460p:~/working_dir/docker_bolt$ tree
.
└── Boltdir
    ├── bolt.yaml
    ├── Dockerfile
    ├── inventory.yaml
    ├── keys
    │   └── id_rsa-acceptance
    └── site-modules
        └── docker_task
            └── tasks
                └── init.sh

5 directories, 5 files
```

**Dockerfile**

```Dockerfile
FROM puppet-bolt

COPY . /Boltdir
```
The following invocation shows building a container image with our custom module content and tagging it `my-extended-puppet-bolt`. 
```
cas@cas-ThinkPad-T460p:~/working_dir/docker_bolt/Boltdir$ docker build . -t my-extended-puppet-bolt
Sending build context to Docker daemon  10.75kB
Step 1/2 : FROM puppet-bolt
 ---> 5d8d2c1166fc
Step 2/2 : COPY . /Boltdir
 ---> 03162d29a1ee
Successfully built 03162d29a1ee
Successfully tagged my-extended-puppet-bolt:latest
```
You can now run that container with the custom module content and connection information available inside the container. For example:
```
cas@cas-ThinkPad-T460p:~/working_dir/docker_bolt/Boltdir$ docker run my-extended-puppet-bolt task run docker_task message=hi -t docker-example
Started on pnz2rzpxfzp95hh.delivery.puppetlabs.net...
Finished on pnz2rzpxfzp95hh.delivery.puppetlabs.net:
  Message: hi
  {
  }
Successful on 1 node: pnz2rzpxfzp95hh.delivery.puppetlabs.net
Ran on 1 node in 0.56 seconds
```