# These faux plugins make NFS mount in an easy read-write capacity.

module VagrantPlugins
  module ValkyrieMount
    module Action
      class ValkyrieMount

        def initialize(app, env)
          @app = app
          @machine = env[:machine]
          @ui = env[:ui]
          @logger = Log4r::Logger.new("ValkyrieMount::action::ValkyrieMount")
        end

        def call(env)
          semaphore = ".valkyrie/cache/first_run_complete"
          machine_action = env[:machine_action]
          if machine_action == :up
            if !File.exist?(semaphore)

              @ui.info "Setting up SSH access for the 'ubuntu' user."
              @machine.communicate.sudo("cp /home/vagrant/.ssh/authorized_keys /home/ubuntu/.ssh/authorized_keys")
              @machine.communicate.sudo("chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys")
              @machine.communicate.sudo("chmod 600 /home/ubuntu/.ssh/authorized_keys")

              @ui.info "Refreshing SSH connection, to login as 'ubuntu'."
              @machine.communicate.instance_variable_get(:@connection).close
              @machine.config.ssh.username = 'ubuntu'

              @ui.info "Installing Ansible from sources."
              ansible_bootstrap = "https://raw.githubusercontent.com/GetValkyrie/ansible-bootstrap/master/install-ansible.sh"
              install_ansible = "curl -s #{ansible_bootstrap} | /bin/sh"
              @machine.communicate.sudo(install_ansible) do |type, data|
                if !data.chomp.empty?
                  @machine.ui.info(data.chomp)
                end
              end

              @ui.info "Running Ansible playbook to re-map users and groups."
              @machine.communicate.upload('mount.yml', "/tmp/mount.yml")
              @machine.communicate.upload('inventory', "/tmp/inventory")
              ansible_playbook = "PYTHONUNBUFFERED=1 "
              ansible_playbook << "ANSIBLE_FORCE_COLOR=true "
              ansible_playbook << "ansible-playbook "
              ansible_playbook << "/tmp/mount.yml "
              ansible_playbook << "-i /tmp/inventory "
              ansible_playbook << "--connection=local "
              ansible_playbook << "--sudo "
              @machine.communicate.sudo(ansible_playbook) do |type, data|
                if !data.chomp.empty?
                  @machine.ui.info(data.chomp)
                end
              end

              @ui.info "Refreshing SSH connection, to login normally."
              @machine.communicate.instance_variable_get(:@connection).close

              @ui.info "Writing semaphore file."
              system("date > #{semaphore}")

            end
          end
        end
      end
    end
  end
end

module VagrantPlugins
  module ValkyrieMount
    class Plugin < Vagrant.plugin('2')
      name 'ValkyrieMount'
      description <<-DESC
        Improve NFS workflows for local dev.
      DESC

      action_hook("ValkyrieMount", :machine_action_up) do |hook|
        hook.append(Action::ValkyrieMount)
      end

    end
  end
end
