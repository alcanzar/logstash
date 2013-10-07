require 'socket'
require "logstash/management/commands"
class LogStash::Management
  include LogStash::ManagementCommands
  
  def self.manage_agent(agent)
    Thread.start do
      server = TCPServer.new agent.management_port
      loop do
        Thread.start(server.accept) do |client|
          data = client.readline.strip
          begin
            if(LogStash::ManagementCommands.methods.include?(:"#{data}"))
              client.puts LogStash::ManagementCommands.method("#{data}").call
            else
              client.puts "Command #{data} does not exist."
            end
          rescue => e
            client.puts e
            client.close
          end
        end
      end
    end
  end
end