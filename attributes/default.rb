default['kdump-conf']['nfs_server'] = 'bipin.local.com'
default['kdump-conf']['dump_corepath'] = '/dumps'
default['kdump-conf']['dump_location'] = "#{node['kdump-conf']['dump_corepath']}/kernel-dumps"
default['kdump-conf']['dump_on_remote'] = true
default['kdump-conf']['dump_local_path'] = '/var/core-dump'
