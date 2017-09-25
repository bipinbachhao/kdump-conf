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
      not_if "grep -q crashkernel=#{crash_kernel_size} /boot/grub/grub.conf"
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

    blklist = 'dm_multipath,hpwdt,ata_piix,libiscsi_tcp,qla4xxx,libiscsi,scsi_transport_iscsi"'

    ruby_block 'Adding_kdump_configuration_in_grub_file' do
      block do
        file = Chef::Util::FileEdit.new('/etc/default/grub')
        file.search_file_replace(/crashkernel=[[:graph:]]+/, "crashkernel=#{crash_kernel_size}")
        file.write_file
      end
      not_if "grep -q crashkernel=#{crash_kernel_size} /etc/default/grub"
      notifies :run, 'execute[grub2-mkconfig]', :immediately
    end

    execute 'grub2-mkconfig' do
      command 'grub2-mkconfig -o /boot/grub2/grub.cfg'
      action :nothing
    end

    ruby_block 'kdump_driver_blacklist_append' do
      block do
        file = Chef::Util::FileEdit.new('/etc/sysconfig/kdump')
        file.search_file_replace(/(^KDUMP_COMMANDLINE_APPEND.*)"/, '\1'" rd.driver.blacklist=#{blklist}")
        file.write_file
      end
      not_if "grep '^KDUMP_COMMANDLINE_APPEND' /etc/sysconfig/kdump|grep -q rd.driver.blacklist=dm_multipath,hpwdt,ata_piix,libiscsi_tcp,qla4xxx"
    end

    ruby_block 'kdump_driver_post_append' do
      block do
        file = Chef::Util::FileEdit.new('/etc/sysconfig/kdump')
        file.search_file_replace(/(^KDUMP_COMMANDLINE_APPEND.*)"/, '\1 rd.driver.post=ixgbe"')
        file.write_file
      end
      only_if 'lspci -v | grep -q ixgbe'
      not_if "grep '^KDUMP_COMMANDLINE_APPEND' /etc/sysconfig/kdump|grep -q rd.driver.post=ixgbe"
    end

    if dump_on_remote
      crashtype = 'nfs'
      corepath = dump_corepath
      msglevel = ' --message-level 15'
      location = "#{nfs_server}:#{dump_location}"

      directory '/usr/coredumps' do
        owner 'root'
        group 'root'
        mode '0755'
        not_if { File.exist?('/usr/coredumps') }
      end

      mount '/usr/coredumps' do
        device "#{guts_svr}:/#{guts_path}/coredumps"
        fstype 'nfs'
        dump 0
        pass 0
        options 'nolock,_netdev'
        action %i[mount enable]
      end

      bash 'systemd-fstab-generator' do
        code <<-CODED
        /usr/lib/systemd/system-generators/systemd-fstab-generator
        CODED
        not_if 'mount |grep -q /usr/coredumps'
      end

    else
      crashtype = crash_filesystem
      corepath = dump_local_path
      msglevel = ''
      location = root_disk
    end

    if network_driver == 'bnx2'
      cookbook_file '/var/crash/kdump-pre-route-add.sh' do
        source 'kdump-pre-route-add.sh'
        mode '0655'
        owner 'root'
        group 'root'
      end
      pre_kdump = 'kdump_pre /var/crash/kdump-pre-route-add.sh'
    end

    template '/etc/kdump.conf' do
      source 'kdump.conf.erb'
      mode '0644'
      variables(
        crashtype: crashtype,
        location: location,
        corepath: corepath,
        msglevel: msglevel,
        pre_kdump: pre_kdump
      )
    end

  end
end

service 'kdump' do
  action [:enable]
end
