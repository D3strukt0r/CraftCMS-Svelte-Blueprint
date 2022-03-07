#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

for func; do
    if [ -z "$func" ]; then
        continue
    fi

    case $func in
        setup-ssh)
            echo 'Setting up SSH...'

            head -n -3 /etc/ssh/sshd_config > tmp.txt && mv tmp.txt /etc/ssh/sshd_config
            #sed -i -e '/PasswordAuthentication yes/s/^#//' /etc/ssh/sshd_config
            # Disable DNS lookups
            sed -i -e '/UseDNS no/s/^#//' /etc/ssh/sshd_config
            # Disable negotation of slow GSSAPI
            sed -i -e '/GSSAPIAuthentication no/s/^#//' /etc/ssh/sshd_config

            systemctl restart ssh
            ;;
        install-docker)
            echo 'Installing Docker onto machine...'

            # Setup repository
            apt-get update -qq >/dev/null
            apt-get install -y -qq \
                ca-certificates \
                curl \
                gnupg \
                lsb-release >/dev/null
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
                $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

            # Install Docker
            apt-get update -qq >/dev/null
            apt-get install -y -qq docker-ce docker-ce-cli containerd.io >/dev/null

            # Manage Docker as a non-root user
            getent group docker >/dev/null || groupadd docker
            usermod -aG docker vagrant

            # Configure Docker to start on boot
            systemctl enable docker.service
            systemctl enable containerd.service
            ;;
        install-docker-compose)
            echo 'Installing Docker Compose onto machine...'
            curl -fsSL "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
            chmod +x /usr/bin/docker-compose
            ;;
        docker-login)
            echo 'Logging into Docker Hub...'
            # TODO: Still insecure
            echo $PASSWORD | docker login --username $USERNAME --password-stdin
            ;;
        cd-to-project)
            echo 'Changing directory to project...'
            echo 'cd /vagrant' >>~/.bashrc
            ;;
        *)
            echo "Unknown function: $func"
            exit 1
            ;;
    esac
done
