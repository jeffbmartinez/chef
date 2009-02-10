#
# Author:: Bryan McLellan (btm@loftninjas.org)
# Copyright:: Copyright (c) 2009 Bryan McLellan
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/provider/service'
require 'chef/mixin/command'

class Chef
  class Provider
    class Service
      class Freebsd < Chef::Provider::Service::Init

        def load_current_resource
          @current_resource = Chef::Resource::Service.new(@new_resource.name)
          @current_resource.service_name(@new_resource.service_name)

          # Determine if we're talking about /etc/rc.d or /usr/local/etc/rc.d
          if ::File.exists?("/etc/rc.d/#{current_resource.service_name}")
            @init_command = "/etc/rc.d/#{current_resource.service_name}" 
          elsif ::File.exists?("/usr/local/etc/rc.d/#{current_resource.service_name}")
            @init_command = "/usr/local/etc/rc.d/#{current_resource.service_name}" 
          else
            raise Chef::Exception::Service, "#{@new_resource}: unable to locate the rc.d script"
          end
          Chef::Log.debug("#{@current_resource.name} found at #{@init_command}")
            
          if @new_resource.supports[:status]
            Chef::Log.debug("#{@new_resource} supports status, checking state")

            begin
              if run_command(:command => "#{@init_command} status") == 0
                @current_resource.running true
              end
            rescue Chef::Exception::Exec
              @current_resource.running false
              nil
            end

          elsif @new_resource.status_command
            Chef::Log.debug("#{@new_resource} doesn't support status but you have specified a status command, running..")

            begin
              if run_command(:command => @new_resource.status_command) == 0
                @current_resource.running true
              end
            rescue Chef::Exception::Exec
              @current_resource.running false
              nil
            end

          else
            Chef::Log.debug("#{@new_resource} does not support status and you have not specified a status command, falling back to process table inspection")

            if @node[:command][:ps].nil? or @node[:command][:ps].empty?
              raise Chef::Exception::Service, "#{@new_resource}: could not determine how to inspect the process table, please set this nodes 'ps' attribute"
            end

            status = popen4(@node[:command][:ps]) do |pid, stdin, stdout, stderr|
              stdin.close
              r = Regexp.new(@new_resource.pattern)
              Chef::Log.debug("#{@new_resource}: attempting to match #{@new_resource.pattern} (#{r}) against process table")
              stdout.each_line do |line|
                if r.match(line)
                  @current_resource.running true
                  break
                end
              end
              @current_resource.running false unless @current_resource.running
            end
            unless status.exitstatus == 0
              raise Chef::Exception::Service, "Command #{@node[:command][:ps]} failed"
            else
              Chef::Log.debug("#{@new_resource}: #{@node[:command][:ps]} exited and parsed succesfully, process running: #{@current_resource.running}")
            end
          end

          if ::File.exists?("/etc/rc.conf")
            read_rc_conf.each do |line|
              case line
              when /#{current_resource.service_name}_enable="(\w+)"/
                if $1 =~ /[Yy][Ee][Ss]/
                  @current_resource.enabled true
                elsif $1 =~ /[Nn][Oo][Nn]?[Oo]?[Nn]?[Ee]?/
                  @current_resource.enabled false
                end
              end
            end
          end
          unless @current_resource.enabled
            Chef::Log.debug("#{@new_resource.name} enable/disable state unknown")
          end
                  
          @current_resource
        end

        def read_rc_conf
          ::File.open("/etc/rc.conf", 'r') { |file| file.readlines }
        end
        
        def write_rc_conf(lines)
          ::File.open("/etc/rc.conf", 'w') do |file|
            lines.each { |line| file.puts(line) }
          end
        end
        
        def enable_service()
          unless @current_resource.enabled 
            lines = read_rc_conf
            lines.collect! do |line|
              if line =~ /#{current_resource.service_name}_enable/
                line = "#{current_resource.service_name}_enable=\"YES\""
              else 
                line = line
              end
            end
            write_rc_conf(lines)
          end
        end

        def disable_service()
          if @current_resource.enabled
            lines = read_rc_conf
            lines.collect! do |line|
              if line =~ /#{current_resource.service_name}_enable/
                line = "#{current_resource.service_name}_enable=\"NO\""
              else 
                line = line
              end
            end
            write_rc_conf(lines)
          end 
        end
     
      end
    end
  end
end
