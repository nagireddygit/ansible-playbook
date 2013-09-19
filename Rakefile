#!/usr/bin/env rake
require 'fileutils'

desc 'Download the required Vagrant image (warning: takes a while)'
task :download do
  system('vagrant box add pl_centos64_rletters http://puppet-vagrant-boxes.puppetlabs.com/centos-64-x64-vbox4210-nocm.box')
end

desc 'Bring up a new vagrant VM'
task :up do
  system('vagrant up')
end

desc 'Bring down the vagrant VM'
task :down do
  system('vagrant halt')
  system('vagrant destroy -f')

  # Remove all the password files
  FileUtils.rm_f File.join('deploy', 'roles', 'db', 'files', 'db_192.168.111.222_pass')
  FileUtils.rm_f File.join('deploy', 'roles', 'solr', 'files', 'tomcat_192.168.111.222_pass')
  FileUtils.rm_f File.join('deploy', 'roles', 'web', 'files', 'deploy_192.168.111.222_pass')
end
