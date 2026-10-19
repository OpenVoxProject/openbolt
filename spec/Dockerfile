FROM ubuntu:26.04

ARG PUPPET_COLLECTION
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates locales openssh-server sudo tree wget \
    && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN locale-gen en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8

# Install the agent package when a collection is given
RUN if [ -n "$PUPPET_COLLECTION" ]; then \
    wget -q https://apt.voxpupuli.org/${PUPPET_COLLECTION}-release-ubuntu26.04.deb \
    && apt-get install -y ./${PUPPET_COLLECTION}-release-ubuntu26.04.deb \
    && apt-get update \
    && apt-get install -y openvox-agent \
    && rm -rf /var/lib/apt/lists/* ; \
    fi

# The tests log in as root with a password
RUN mkdir -p /run/sshd \
    && echo "root:root" | chpasswd \
    && printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/10-bolt-tests.conf

# Add 'bolt' user
RUN useradd bolt
RUN echo "bolt:bolt" | chpasswd
RUN usermod -aG sudo bolt

RUN mkdir -p /home/bolt/.ssh
COPY fixtures/keys/id_rsa.pub /home/bolt/.ssh/id_rsa.pub
COPY fixtures/keys/id_rsa.pub /home/bolt/.ssh/authorized_keys
RUN chmod 700 /home/bolt/.ssh
RUN chmod 600 /home/bolt/.ssh/authorized_keys
RUN chown -R bolt:sudo /home/bolt

# Add 'test' user with different login shell
RUN useradd -s /bin/bash test
RUN echo "test:test" | chpasswd
RUN usermod -aG sudo test

RUN mkdir -p /home/test/.ssh
COPY fixtures/keys/id_rsa.pub /home/test/.ssh/id_rsa.pub
COPY fixtures/keys/id_rsa.pub /home/test/.ssh/authorized_keys
RUN chmod 700 /home/test/.ssh
RUN chmod 600 /home/test/.ssh/authorized_keys
RUN chown -R test:sudo /home/test

EXPOSE 22

# Run the sshd service in the foreground, logging to stderr
CMD [ "/usr/sbin/sshd", "-D", "-e" ]
