# -*- encoding : utf-8 -*-
require 'spec_helper'
require 'net/http'

describe 'Ansible provisioning' do
  before(:all) do
    system('rake up')
    system('cd deploy && ansible-playbook -c paramiko -v -i hosts.testing site.yml')
  end

  after(:all) do
    system('rake down')
  end

  describe 'common role' do
    describe 'ntp.yml' do
      it 'starts the NTP service' do
        expect(vagrant_ssh('/etc/init.d/ntpd status')).to match(/ntpd .* is running\.\.\./)
      end

      it 'does not make the NTP daemon publically accessible' do
        vagrant_check_port_closed(123)
      end

      it 'synchronizes to a time server' do
        expect(vagrant_ssh("ntpq -np | grep -E '((25[0-5]|2[0-4][0-9]|[1]?[1-9][0-9]?).){3}(25[0-5]|2[0-4][0-9]|[1]?[1-9]?[0-9])'")).to_not be_empty
      end
    end
  end

  describe 'db role' do
    describe 'main.yml' do
      it 'successfully installs postgresql' do
        expect(vagrant_ssh('which psql')).to start_with("/usr/bin/psql")
      end

      it 'creates the database password file' do
        file_path = './deploy/roles/db/files/db_127.0.0.1_pass'
        expect(File.exist?(file_path)).to be true
      end

      it 'creates the database and user' do
        file_path = './deploy/roles/db/files/db_127.0.0.1_pass'
        db_password = IO.read(file_path)
        db_password.gsub!('\\', '\\\\')
        db_password.gsub!(':', '\:')

        # Set the password on the server for passwordless authentication
        vagrant_ssh("echo '*:*:*:*:#{db_password}' > ~/.pgpass")
        vagrant_ssh('chmod 0600 ~/.pgpass')

        # Make sure the database exists and the user can connect
        expect(vagrant_ssh('psql -h 127.0.0.1 -d rletters_production -U rletters_postgresql -c \\\\\\list')).to match(/ rletters_production /)

        # Clean up the authentication file
        vagrant_ssh('rm ~/.pgpass')
      end

      it 'does not make the PostgreSQL server publically accessible' do
        # Since the web server and DB server are both on the same host, the
        # scripts should *not* open port 5432 through iptables.
        vagrant_check_port_closed(5432)
      end
    end
  end

  describe 'solr role' do
    describe 'tomcat.yml' do
      it 'installs the Tomcat native library' do
        expect(vagrant_ssh('ls /usr/lib64/libtcnative-1.so')).to start_with("/usr/lib64/libtcnative-1.so")
      end

      it 'actually uses the Tomcat native library' do
        expect(vagrant_ssh('grep \'Loaded APR based\' /opt/tomcat/logs/catalina.out')).to_not be_empty
      end

      it 'starts the Tomcat server' do
        expect(vagrant_ssh('/etc/init.d/tomcat status')).to include('Tomcat is running')
      end

      it 'makes Tomcat functional' do
        expect(vagrant_ssh('wget -q -O- http://localhost:8080')).to include('<title>Apache Tomcat/7')
      end

      it 'creates the Tomcat password file' do
        file_path = './deploy/roles/solr/files/tomcat_127.0.0.1_pass'
        expect(File.exist?(file_path)).to be true
      end

      it 'configures the Tomcat administration GUI' do
        file_path = './deploy/roles/solr/files/tomcat_127.0.0.1_pass'
        tomcat_password = IO.read(file_path).sub("\n", '')

        expect(vagrant_ssh("wget -q -O- http://rletters_tomcat:#{tomcat_password}@localhost:8080/manager/html")).to include('<title>/manager</title>')
      end

      it 'does not make the Tomcat server publically accessible' do
        # Since the web server and Solr server are both on the same host, the
        # scripts should *not* open port 8080 through iptables.
        vagrant_check_port_closed(8080)
      end
    end

    describe 'solr.yml' do
      it 'makes Solr functional' do
        expect(vagrant_ssh('wget -q -O- http://localhost:8080/solr/search?q=test')).to include('<lst name="responseHeader">')
      end

      it 'installs the Solr configuration' do
        # If the result contains one of our facet queries for years, then we
        # know that the configuration has been installed correctly
        expect(vagrant_ssh('wget -q -O- http://localhost:8080/solr/search?q=test')).to include('<int name="year:[1940 TO 1949]">')
      end

      # We can't do any further tests without there being some documents, which
      # we can't guarantee, so this will have to do.  (We can't, e.g., check
      # that we're operting on the right schema.)
    end
  end

  describe 'web role' do
    describe 'ruby.yml' do
      it 'successfully installs ruby' do
        expect(vagrant_ssh('which ruby')).to start_with("/usr/local/bin/ruby")
      end

      it 'successfully installs gem' do
        expect(vagrant_ssh('which gem')).to start_with("/usr/local/bin/gem")
      end

      it 'successfully installs bundler' do
        expect(vagrant_ssh('which bundle')).to start_with("/usr/local/bin/bundle")
      end
    end

    describe 'user.yml' do
      it 'successfully creates the rletters_deploy user' do
        expect(vagrant_ssh('cat /etc/passwd | grep rletters_deploy')).to_not be_empty
      end

      it 'assigns /opt/rletters to that user' do
        expect(vagrant_ssh('ls -ld /opt/rletters')).to include(' rletters_deploy ')
      end
    end

    describe 'rletters.yml' do
      it 'checks out RLetters' do
        expect(vagrant_ssh('sudo ls /opt/rletters/root/Gemfile')).to start_with("/opt/rletters/root/Gemfile")
      end

      it 'installs the bundle in the state directory' do
        expect(vagrant_ssh('sudo ls /opt/rletters/state/bundle')).to start_with("ruby")
      end

      it 'creates the database.yml file pointing at localhost' do
        expect(vagrant_ssh('sudo cat /opt/rletters/root/config/database.yml')).to include("host: '127.0.0.1'")
      end

      it 'makes the NLP tool file' do
        expect(vagrant_ssh('sudo ls /opt/rletters/root/vendor/nlp/nlp-tool')).to start_with("/opt/rletters/root/vendor/nlp/nlp-tool")
      end

      it 'installs working NLP tool' do
        expect(vagrant_ssh('sudo sh -c \'echo were | /opt/rletters/root/vendor/nlp/nlp-tool -l\'')).to include("---\n- \"be\"\n")
      end
    end

    describe 'bluepill.yml' do
      it 'installs Bluepill globally' do
        expect(vagrant_ssh('which bluepill')).to start_with("/usr/local/bin/bluepill")
      end

      it 'creates the Bluepill configuration' do
        expect(vagrant_ssh('sudo ls /opt/bluepill/bluepill.rb')).to start_with("/opt/bluepill/bluepill.rb")
      end

      it 'creates the resque-pool configuration' do
        expect(vagrant_ssh('sudo ls /opt/bluepill/resque-pool.yml')).to start_with("/opt/bluepill/resque-pool.yml")
      end

      it 'creates the Puma configuration' do
        expect(vagrant_ssh('sudo ls /opt/bluepill/puma.rb')).to start_with("/opt/bluepill/puma.rb")
      end
    end

    describe 'nginx.yml' do
      it 'opens port 80' do
        vagrant_check_port_open(80)
      end

      it 'serves the index page locally' do
        expect(vagrant_ssh('wget -q -O- http://localhost')).to include('<!DOCTYPE html>')
      end

      it 'serves the index page remotely' do
        Net::HTTP.start('127.0.0.1', 8888) do |http|
          request = Net::HTTP::Get.new(URI('http://127.0.0.1:8888/'))
          response = http.request request

          expect(response.body).to include('<!DOCTYPE html>')
          expect {
            response.value
          }.to_not raise_error
        end
      end

      it 'serves one of the application pages remotely' do
        Net::HTTP.start('127.0.0.1', 8888) do |http|
          request = Net::HTTP::Get.new(URI('http://127.0.0.1:8888/search/'))
          response = http.request request

          expect(response.body).to include('<!DOCTYPE html>')
          expect {
            response.value
          }.to_not raise_error
        end
      end
    end
  end

  describe 'redis role' do
    describe 'main.yml' do
      it 'installs Redis' do
        expect(vagrant_ssh('which redis-server')).to start_with("/usr/sbin/redis-server")
      end

      it 'starts Redis' do
        expect(vagrant_ssh('redis-cli ping')).to start_with("PONG")
      end

      it 'does not make the Redis server publically accessible' do
        vagrant_check_port_closed(6379)
      end
    end
  end
end
