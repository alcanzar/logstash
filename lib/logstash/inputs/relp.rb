require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/util/socket_peer"
require "socket"
require "timeout"
#TODO: make sure to remove this before release
require "pry"

# Read RELP events over a TCP socket.
#
#
class LogStash::Inputs::Relp < LogStash::Inputs::Base

  config_name "relp"
  plugin_status "experimental"

  # The address to listen on.
  config :host, :validate => :string, :default => "0.0.0.0"

  # The port to listen on.
  config :port, :validate => :number, :required => true

  def initialize(*args)
    super(*args)
  end # def initialize

  public
  def register
    @logger.info("Starting relp input listener", :address => "#{@host}:#{@port}")
    @server_socket = TCPServer.new(@host, @port)
  end # def register

  #give it a socket, it'll wait for a relp open frame and do the handshake
  private
  def relp_initialise(socket)
    #TODO: while this logic works, it's not very readable- exeptions are probably a better thing to do
    frame=relp_frame_read(socket)
    if frame.nil?
      return false
    elsif frame==false
      return false
    elsif frame['command']!='open'
      return false
    else
      @logger.debug("Recieved relp offer: #{frame.to_s}")
      offer=Hash[*frame['message'].scan(/^(.*)=(.*)$/).flatten]
      if offer['relp_version'].nil?
        #if no version specified, relp spec says we must close connection
        relp_serverclose(socket)
        return false
      elsif ! offer['commands'].split(',').include?('syslog')
        #if it can't send us syslog it's useless to us; close the connection
        relp_serverclose(socket)
        return false
      else
        #attempt to set up connection
        response_frame=Hash.new
        response_frame['txnr']=frame['txnr']
        response_frame['command']='rsp'
        #TODO: the values in this message probably ought to be constants defined at the top somewhere
        response_frame['message']='200 OK relp_version=0'+"\n"+'relp_software=logstash,1.0.0,http://logstash.net'+"\n"+'commands=syslog'
        begin
          relp_frame_write(socket,response_frame)
          return true
        rescue
          @logger.warning('Broken connection with '+socket.peer)
          return false
        end
      end
    end
#TODO: give a meaningful return value
  end

  private
  def relp_stream(socket,output_queue,event_source)
    loop do
      frame=relp_frame_read(socket)

      if frame['command']=='syslog'
        event=self.to_event(frame['message'],event_source)
        output_queue << event
        #To get this far, the message must have made it into the queue for filtering. I don't think it's possible to wait for output before ack without fundamentally breaking the plugin architecture
        relp_ack(socket,frame['txnr'])
      elsif frame['command']=='close'
        #the client is closing the connection, acknowledge the close and act on it
        response_frame=Hash.new
        response_frame['txnr']=frame['txnr']
        response_frame['command']='rsp'
        relp_frame_write(socket,response_frame)
        relp_serverclose(socket)
        #TODO: completed without errors?
        return 0
      else
        #the client is trying to do something else, we can either ignore it or send it serverclose
        #TODO: we should have cases for all basic commands, anything else we didn't offer should cause a serverclose right?
        relp_serverclose(socket)
        #TODO: sort out these error codes
        return 1
      end
    end
  end

  private
  def relp_frame_read(socket)
    #TODO: what if the data does not form a valid relp frame? we also need to sort ourselves out if we end up misaligned with the frames
    frame=Hash.new
    frame['txnr']=socket.readline(' ').strip.to_i
    frame['command']=socket.readline(' ').strip

    #Things get a little tricky here because if the length is 0 it is not followed by a space.
    leading_digit=socket.read(1)
    if leading_digit=='0' then
      frame['datalen']=0
      frame['message']=''
    else
      frame['datalen']=(leading_digit + socket.readline(' ')).strip.to_i
      frame['message']=socket.read(frame['datalen'])
    end

    frame
  end

  private
  def relp_serverclose(socket)
    frame=Hash.new
    frame['txnr']=0
    frame['command']='serverclose'
    relp_frame_write(socket,frame)
    socket.close
  end

  #frame is a hash including at minimum txnr,command and optionally message
  private
  def relp_frame_write(socket,frame)
    frame['txnr']=frame['txnr'].to_s
    frame['message']='' if frame['message'].nil?
    frame['datalen']=frame['message'].length.to_s
    wiredata=[frame['txnr'],frame['command'],frame['datalen'],frame['message']].join(' ').strip+"\n"
    #Ending each frame with a newline is required in the specifications
    socket.write(wiredata)
  end

  #send a 200 OK response for txnr to socket
  private
  def relp_ack(socket,txnr)
    frame=Hash.new
    frame['txnr']=txnr
    frame['command']='rsp'
    frame['message']='200 OK'
    relp_frame_write(socket,frame)
  end

  public
  def run(output_queue)
    loop do
      # Start a new thread for each connection.
      Thread.start(@server_socket.accept) do |s|

        # monkeypatch a 'peer' method onto the socket. I think this is just used for constructing the event_source below, not sure
        s.instance_eval { class << self; include ::LogStash::Util::SocketPeer end }
        @logger.debug("Accepted connection", :client => s.peer,
                      :server => "#{@host}:#{@port}")
        begin
          if relp_initialise(s)
            relp_stream(s,output_queue,"relp://#{@host}:#{@port}/s.peer")
          end
#TODO: deal with stream unexpectedly closing
        rescue
          puts 'rescue'
#TODO: what if the socket is already closed?
          socket.close
        end
      end # Thread.start
    end # loop
  end # def run
end # class LogStash::Inputs::Relp
