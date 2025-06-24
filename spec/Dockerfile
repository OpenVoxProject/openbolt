FROM ubuntu:24.04

ARG PUPPET_COLLECTION

# Install required packages
RUN apt update \
    && apt install -y --no-install-recommends \
        adduser \
        ca-certificates \
        openssh-server \
        libssl-dev \
        sudo \
        locales \
        wget \
        apt-transport-https \
        tree \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Set the locale
RUN locale-gen en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8

# Install the puppet-agent package
# sudo is important here so puppet is added to the path
RUN if [ -n "$PUPPET_COLLECTION" ]; then \
    wget -q https://apt.voxpupuli.org/${PUPPET_COLLECTION}-release-ubuntu24.04.deb \
    && sudo apt install -y /${PUPPET_COLLECTION}-release-ubuntu24.04.deb \
    && sudo apt update \
    && sudo apt install -y openvox-agent ; \
    fi

# Add 'bolt' user
RUN useradd bolt
RUN echo "bolt:bolt" | chpasswd
RUN adduser bolt sudo

RUN mkdir -p /home/bolt/.ssh
COPY fixtures/keys/id_rsa.pub /home/bolt/.ssh/id_rsa.pub
COPY fixtures/keys/id_rsa.pub /home/bolt/.ssh/authorized_keys
RUN chmod 700 /home/bolt/.ssh
RUN chmod 600 /home/bolt/.ssh/authorized_keys
RUN chown -R bolt:sudo /home/bolt

# Add 'test' user with different login shell
RUN useradd test
RUN echo "test:test" | chpasswd
RUN adduser test sudo
RUN echo test | chsh -s /bin/bash test

RUN mkdir -p /home/test/.ssh
COPY fixtures/keys/id_rsa.pub /home/test/.ssh/id_rsa.pub
COPY fixtures/keys/id_rsa.pub /home/test/.ssh/authorized_keys
RUN chmod 700 /home/test/.ssh
RUN chmod 600 /home/test/.ssh/authorized_keys
RUN chown -R test:sudo /home/test

# Run the sshd service in the background
RUN echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config.d/pubkey_auth.conf && \
    echo "LogLevel VERBOSE" >> /etc/ssh/sshd_config.d/log_level.conf

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
