#
# Cookbook Name:: nsca
# Recipe:: default
# Author:: Felipe Cecagno (<felipe@mconf.org>)
#
# This file is part of the Mconf project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

%w{ zlib1g-dev libmcrypt-dev }.each do |pkg|
  package pkg do
    action :install
  end
end

if node[:nsca][:force_reinstall]
  file "#{Chef::Config[:file_cache_path]}/nsca-#{node[:nsca][:version]}.tar.gz" do
    action :delete
  end
  directory "#{Chef::Config[:file_cache_path]}/nsca-#{node[:nsca][:version]}" do
    recursive true
    action :delete
  end
  node.set[:nsca][:force_reinstall] = false
end

cookbook_file "#{Chef::Config[:file_cache_path]}/nsca.c.v2.9.1.patched" do
  source "nsca.c.v2.9.1.patched"
  mode "0644"
end

# get nsca file from server and call build script if there is a new file
remote_file "#{Chef::Config[:file_cache_path]}/nsca-#{node[:nsca][:version]}.tar.gz" do
    source "http://prdownloads.sourceforge.net/sourceforge/nagios/nsca-#{node[:nsca][:version]}.tar.gz"
    mode "0644"
    notifies :run, 'script[build nsca]', :immediately
end

# build nsca and call installer
script "build nsca" do
    action :nothing
    interpreter "bash"
    user "root"
    cwd "#{Chef::Config[:file_cache_path]}"
    code <<-EOH
        tar xzf "nsca-#{node[:nsca][:version]}.tar.gz"
        cd "nsca-#{node[:nsca][:version]}"
        # for some reason, patch isn't working properly
        # \TODO instead of using the complete file patched, use only the patch
#        mv #{Chef::Config[:file_cache_path]}/nsca.c.patch src/
#        patch src/nsca.c < src/nsca.c.patch

        if [ "#{node[:nsca][:version]}" == "2.9.1" ]; then
          mv #{Chef::Config[:file_cache_path]}/nsca.c.v2.9.1.patched src/nsca.c
        fi
        ./configure
        make all
        make install
    EOH
    notifies :run, 'script[install nsca]', :immediately
end

# nsca install procedure 
script "install nsca" do
    action :nothing
    interpreter "bash"
    user "root"
    cwd "#{Chef::Config[:file_cache_path]}/nsca-#{node[:nsca][:version]}"
    code <<-EOH
        mkdir -p #{node[:nsca][:dir]} #{node[:nsca][:config_dir]}
        cp src/send_nsca #{node[:nsca][:dir]}
        cp sample-config/send_nsca.cfg #{node[:nsca][:config_dir]}/
        chmod +r #{node[:nsca][:config_dir]}/send_nsca.cfg
    EOH
end