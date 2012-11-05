# Cookbook Name:: mconf-monitor
# Recipe:: default
#
# Copyright 2012, mconf.org
#
# All rights reserved - Do Not Redistribute
#

include_recipe "psutil"

%w{ zlib1g-dev git-core python-dev python-argparse subversion libmcrypt4 }.each do |pkg|
  package pkg do
    action :install
  end
end

include_recipe "bigbluebutton::load-properties"

t = ruby_block "set nagios properties" do
    block do
        if node[:mconf][:instance_type] == "bigbluebutton"
            node.set[:mconf][:hostname] = "#{node[:bbb][:server_domain]}"
            node.set[:mconf][:nagios_message] = "#{node[:mconf][:instance_type]} #{node[:bbb][:server_url]}/bigbluebutton/ #{node[:bbb][:salt]}"
        else
            if node[:mconf][:instance_type] == "nagios"
                node.set[:mconf][:hostname] = "localhost"
            else
                node.set[:mconf][:hostname] = node[:ipaddress]
            end
            node.set[:mconf][:nagios_message] = "#{node[:mconf][:instance_type]}"
        end
    end
end

t.run_action(:create)

directory "#{node[:mconf][:nagios][:dir]}" do
  owner "#{node[:mconf][:user]}"
  recursive true
end

#get nsca file from server and call build script if there is a new file
remote_file "#{node[:mconf][:nagios][:dir]}/nsca-#{node[:nsca][:version]}.tar.gz" do
    source "http://prdownloads.sourceforge.net/sourceforge/nagios/nsca-#{node[:nsca][:version]}.tar.gz"
    mode "0644"
    notifies :run, 'script[nsca_build]', :immediately
end

#build nsca and call installer
script "nsca_build" do
    action :nothing
    interpreter "bash"
    user "root"
    cwd "#{node[:mconf][:nagios][:dir]}"
    code <<-EOH
        tar xzf "nsca-#{node[:nsca][:version]}.tar.gz"
        cd "nsca-#{node[:nsca][:version]}"
        ./configure
        make
        make install
    EOH
    notifies :run, 'script[install_nsca]', :immediately
end

#nsca install procedure 
script "install_nsca" do
    action :nothing
    interpreter "bash"
    user "root"
    cwd "#{node[:mconf][:nagios][:dir]}/nsca-#{node[:nsca][:version]}"
    code <<-EOH
        mkdir -p #{node[:nsca][:dir]} #{node[:nsca][:config_dir]}
        chown nagios:nagios -R /usr/local/nagios
        cp src/send_nsca #{node[:nsca][:dir]}
        cp sample-config/send_nsca.cfg #{node[:nsca][:config_dir]}/
        chmod a+r #{node[:nsca][:config_dir]}/send_nsca.cfg
    EOH
end

#performance reporter service definition
service "performance_report" do
    provider Chef::Provider::Service::Upstart
    subscribes :restart, resources()
    supports :restart => true, :start => true, :stop => true
end

#performance reporter template creation
template "performance_report upstart" do
    path "/etc/init/performance_report.conf"
    source "performance_report.conf"
    mode "0644"
    notifies :restart, resources(:service => "performance_report"), :delayed
end

template "#{node[:mconf][:nagios][:dir]}/reporter.sh" do
  source "reporter.sh"
  mode 0755
  owner "#{node[:mconf][:user]}"
  action :create
  notifies :restart, resources(:service => "performance_report"), :delayed
end

cookbook_file "#{node[:mconf][:nagios][:dir]}/performance_report.py" do
  source "performance_report.py"
  mode 0755
  owner "#{node[:mconf][:user]}"
  action :create
  notifies :restart, resources(:service => "performance_report"), :delayed
end

execute "server up" do
  user "#{node[:mconf][:user]}"
  command "/usr/bin/printf \"%s\t%s\t%s\t%s\n\" \"localhost\" \"Server UP\" \"3\" \"#{node[:mconf][:nagios_message]}\" | #{node[:mconf][:nagios][:dir]}/reporter.sh && echo \"#{node[:bbb][:server_url]}\" > #{node[:mconf][:nagios][:dir]}/.bbb_url && echo \"#{node[:bbb][:salt]}\" > #{node[:mconf][:nagios][:dir]}/.bbb_salt"
  not_if do
    (File.exists?("#{node[:mconf][:nagios][:dir]}/.bbb_url") and File.read("#{node[:mconf][:nagios][:dir]}/.bbb_url").chomp == "#{node[:bbb][:server_url]}") and \
    (File.exists?("#{node[:mconf][:nagios][:dir]}/.bbb_salt") and File.read("#{node[:mconf][:nagios][:dir]}/.bbb_salt").chomp == "#{node[:bbb][:salt]}")
  end
end
