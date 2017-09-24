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
