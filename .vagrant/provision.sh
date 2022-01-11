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
            #PasswordAuthentication yes
            #UseDNS no
            #GSSAPIAuthentication no
            #sed -i -e '/PasswordAuthentication yes/s/^#//' /etc/ssh/sshd_config
            #sed -i -e '/UseDNS yes/s/^#//' /etc/ssh/sshd_config
            #sed -i -e '/GSSAPIAuthentication yes/s/^#//' /etc/ssh/sshd_config


            #sudo sed -i -e 's/\(PasswordAuthentication\)yes/\1\ no/' /etc/ssh/sshd_config
            #sudo sed -i -e 's/\(PasswordAuthentication\)no/\1\ yes/' /etc/ssh/sshd_config
            #sudo sed -i -e 's/PasswordAuthentication yes/#&/' /etc/ssh/sshd_config
            ;;
        install-docker)
            echo 'Installing Docker onto machine...'

            # Setup repository
            sudo apt-get update -qq >/dev/null
            sudo apt-get install -y -qq \
                ca-certificates \
                curl \
                gnupg \
                lsb-release >/dev/null
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
                $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

            # Install Docker
            sudo apt-get update -qq >/dev/null
            sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io >/dev/null

            # Manage Docker as a non-root user
            getent group docker >/dev/null || sudo groupadd docker
            sudo usermod -aG docker vagrant

            # Configure Docker to start on boot
            sudo systemctl enable docker.service
            sudo systemctl enable containerd.service
            ;;
        install-docker-compose)
            echo 'Installing Docker Compose onto machine...'
            sudo curl -fsSL "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
            sudo chmod +x /usr/bin/docker-compose
            ;;
        *)
            echo "Unknown function: $func"
            exit 1
            ;;
    esac
done
