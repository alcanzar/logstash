require "logstash/inputs/base"
require "logstash/namespace"
require "socket" # for Socket.gethostname

# Read events from standard input.
#
# By default, each event is assumed to be one line. If you
# want to join lines, you'll want to use the multiline filter.
class LogStash::Inputs::Stdin < LogStash::Inputs::Base
  config_name "stdin"
  milestone 3

  default :codec, "line"

  public
  def register
    @host = Socket.gethostname
    @io = IO.new(IO.sysopen("/dev/tty", "r"), "r")
  end # def register

  def run(queue) 
    while true
      begin
        # Based on some testing, there is no way to interrupt an IO.sysread nor
        # IO.select call in JRuby. Bummer :(
        data = @io.sysread(16384)
        @codec.decode(data) do |event|
          decorate(event)
          event["host"] = @host
          queue << event
        end
      rescue EOFError, LogStash::ShutdownSignal
        # stdin closed or a requested shutdown
        break
      end
    end # while true
    finished
  end # def run

  public
  def teardown
    @logger.debug("stdin shutting down.")
    @io.close rescue nil
    finished
  end # def teardown
end # class LogStash::Inputs::Stdin
