require 'yaml'

Vagrant.require_version '>= 2.2.4'

Vagrant.configure('2') do |config|
    # --------------------------------------------------------------------------
    # Check for required plugins
    # --------------------------------------------------------------------------
    plugins_installed = false

    # Vagrant Share allows you to share your Vagrant environment with anyone in
    # the world, enabling collaboration directly in your Vagrant environment in
    # almost any network environment with just a single command
    unless Vagrant.has_plugin?('vagrant-share')
        system('vagrant plugin install vagrant-share')
        plugins_installed = true
    end
    # NOT MAINTAINED! USE AN ALTERNATIVE!
    # This plugin adds an entry to your /etc/hosts file on the host system.
    unless Vagrant.has_plugin?('vagrant-hostsupdater')
        system('vagrant plugin install vagrant-hostsupdater')
        plugins_installed = true
    end
    # A vagrant plugin that uses notify-forwarder to forward file system events
    # from the host to the guest automatically on all shared folders.
    unless Vagrant.has_plugin?('vagrant-notify-forwarder')
        system('vagrant plugin install vagrant-notify-forwarder')
        plugins_installed = true
    end
    # vagrant-vbguest is a Vagrant plugin which automatically installs the
    # host's VirtualBox Guest Additions on the guest system.
    unless Vagrant.has_plugin?('vagrant-vbguest')
        system('vagrant plugin install vagrant-vbguest')
        plugins_installed = true
    end
    # A Vagrant provisioner for Docker Compose. Installs Docker Compose and can
    # also bring up the containers defined by a docker-compose.yml.
    unless Vagrant.has_plugin?('vagrant-docker-compose')
        system('vagrant plugin install vagrant-docker-compose')
        plugins_installed = true
    end

    # For plugins to be detected by vagrant, 'vagrant up' must be rerun.
    if plugins_installed
        puts 'Plugins were installed. Please restart the Vagrant environment.'
        exit
    end

    # --------------------------------------------------------------------------
    # Load configuration
    # --------------------------------------------------------------------------
    settings = YAML.load(File.read('.vagrant-settings.yml'))

    # --------------------------------------------------------------------------
    # Configure the machine
    # --------------------------------------------------------------------------
    config.vm.box = 'bento/ubuntu-21.04'

    config.vm.provider 'virtualbox' do |v|
        # Set the name to show in the GUI
        if settings and settings['vm'] and settings['vm']['name']
            v.name = settings['vm']['name']
        elsif settings and settings['network'] and settings['network']['hostname']
            v.name = settings['network']['hostname']
        end

        # Set the CPU limit
        if settings and settings['vm'] and settings['vm']['cpus']
            v.cpus = settings['vm']['cpus']
        end
        # Set the amount of memory to allocate to the VM
        if settings and settings['vm'] and settings['vm']['memory']
            v.memory = settings['vm']['memory']
        end
    end

    # --------------------------------------------------------------------------
    # Configure the network
    # --------------------------------------------------------------------------
    # Set the main hostname
    if settings and settings['network'] and settings['network']['hostname']
        config.vm.hostname = settings['network']['hostname']
    end
    # Add alternative hostnames
    if Vagrant.has_plugin?('vagrant-hostsupdater')
        if settings and settings['network'] and settings['network']['aliases']
            config.hostsupdater.aliases = settings['network']['aliases']
        end
    end

    # Define main IP address
    if settings and settings['network'] and settings['network']['ip']
        config.vm.network 'private_network', ip: settings['network']['ip']

        if Vagrant.has_plugin?('vagrant-notify-forwarder')
            # This configures the notify-forwarder to a port derived from the IP
            # address to ensure that all running boxes have a different port
            config.notify_forwarder.port = 22000 + settings['network']['ip'].split('.')[2].to_i() + settings['network']['ip'].split('.')[3].to_i()
        end
    else
        config.vm.network 'private_network', type: 'dhcp'
    end

    # --------------------------------------------------------------------------
    # Configure the synced folders
    # --------------------------------------------------------------------------
    if settings and settings['folder'] and settings['folder']['type'] == 'nfs'
        config.vm.synced_folder '.', '/vagrant',
            type: 'nfs',
            nfs_version: 3, # TODO: Update to NFSv4
            nfs_udp: false, # UDP not allowed in NFSv4
            mount_options: ['rw', 'tcp', 'nolock', 'async']
        config.nfs.map_uid = Process.uid
        config.nfs.map_gid = Process.gid
    elsif settings and settings['folder'] and settings['folder']['type'] == 'rsync'
        config.vm.synced_folder '.', '/vagrant',
            type: 'rsync',
            rsync__args: ['--verbose', '--archive', '--delete', '-z'],
            rsync__chown: true,
            rsync__exclude: settings ? settings['folder'] ? settings['folder']['rsync'] ? settings['folder']['rsync']['exclude'] : [] : [] : []

        # An rsync watcher for Vagrant 1.5.1+ that uses fewer host resources at
        # the potential cost of more rsync actions.
        # Configure the window for gatling to coalesce writes.
        if Vagrant.has_plugin?('vagrant-gatling-rsync')
            config.gatling.latency = 1.5
            config.gatling.time_format = '%H:%M:%S'

            # Automatically sync when machines with rsync folders come up.
            config.gatling.rsync_on_startup = false
        end
    else
        config.vm.synced_folder '.', '/vagrant'
    end

    # --------------------------------------------------------------------------
    # Provision the machine
    # --------------------------------------------------------------------------
    config.vm.provision 'file', source: './.vagrant/provision.sh', destination: '/tmp/provision.sh'

    config.vm.provision 'setup-ssh', type: 'shell', inline: '/tmp/provision.sh setup-ssh'

    #config.vm.provision :docker
    #config.vm.provision 'install-docker', type: 'shell', inline: '/tmp/provision.sh install-docker'
    #config.vm.provision :docker_compose, yml: '/vagrant/docker-compose.yml', run: 'always'
    #config.vm.provision 'install-docker-compose', type: 'shell', inline: '/tmp/provision.sh install-docker-compose'

    config.vm.provision 'shell', inline: 'rm /tmp/provision.sh'
end
