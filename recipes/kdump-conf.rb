#
# Cookbook Name:: kdump-conf
# Recipe:: default
#
# Author : Bipin Bachhao
# Email-id : bipinbachhao@gmail.com
#
# Apache 2.0 license
#
#

require 'mixlib/shellout'

nfs_server = node['kdump-conf']['nfs_server']
dump_corepath = node['kdump-conf']['dump_corepath']
dump_location =  node['kdump-conf']['dump_location']
dump_on_remote = node['kdump-conf']['dump_on_remote']
dump_local_path = node['kdump-conf']['dump_local_path']
ram = node['memory']['total'].to_i / 1024
interface = node['network']['default_interface']

# Determine / fstype for local crash
cf = Mixlib::ShellOut.new("df -PT /root|awk '/\\/$/{print $2}'")
crash_filesystem = cf.run_command.stdout.to_s.chomp
rd = Mixlib::ShellOut.new("df -PT /root|awk '/\\/$/{print $1}'")
root_disk = rd.run_command.stdout.to_s.chomp
network_driver = Mixlib::ShellOut.new("ethtool -i #{interface}|grep\
 driver|awk '{print $2}'").run_command.stdout.to_s.chomp

crash_kernel_size = if ram < 2048
                      '192M'
                    else
                      'auto'
                    end

if (node['platform'] == 'redhat') || (node['platform'] == 'centos')
  if (node['platform_version'] >= '6') && (node['platform_version'] < '7')

    # Centos 6 Part
    ruby_block 'Adding_kdump_configuration_in_grub_file' do
      block do
        file = Chef::Util::FileEdit.new('/boot/grub/grub.conf')
        file.search_file_replace(/crashkernel=[[:graph:]]+/, "crashkernel=#{crash_kernel_size}")
        file.write_file
      end
    end

    blklist = 'blacklist dm_multipath hpwdt ata_piix libiscsi_tcp qla4xxx libiscsi scsi_transport_iscsi'

    if dump_on_remote
      crashtype = 'net'
      corepath = dump_corepath
      msglevel = ' --message-level 15'
      location = "#{nfs_server}:#{dump_location}"
    else
      crashtype = crash_filesystem
      corepath = dump_local_path
      location = root_disk
      msglevel = ''
    end

    template '/etc/kdump.conf' do
      source 'kdump.conf.erb'
      mode '0644'
      variables(
        crashtype: crashtype,
        location: location,
        corepath: corepath,
        msglevel: msglevel,
        blklist: blklist
      )
    end

  else
    # Centos 7 Part

    ruby_block 'Adding_kdump_configuration_in_grub_file' do
      block do
        file = Chef::Util::FileEdit.new('/etc/default/grub')
        file.search_file_replace(/crashkernel=[[:graph:]]+/, "crashkernel=#{crash_kernel_size}")
        file.write_file
      end
    end

    execute 'grub2-mkconfig' do
      command 'grub2-mkconfig -o /boot/grub2/grub.cfg'
      action :run
    end

    ruby_block 'kdump_driver_blacklist_append' do
      block do
        file = Chef::Util::FileEdit.new(/etc/sysconfig/kdump)
        file.search_file_replace(/(^KDUMP_COMMANDLINE_APPEND.*)/, )
      end
    end

  end
end
