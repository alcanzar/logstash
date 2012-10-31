require "logstash/outputs/base"
require "logstash/namespace"

# Push events to a GemFire region.
#
# GemFire is an object database.
#
# To use this plugin you need to add gemfire.jar to your CLASSPATH;
# using format=json requires jackson.jar too.
#
# Note: this plugin has only been tested with GemFire 7.0.
#
class LogStash::Outputs::Gemfire < LogStash::Outputs::Base

  config_name "gemfire"
  plugin_status "experimental"

  # Your client cache name
  config :name, :validate => :string, :default => "logstash"

  # A path to a GemFire XML file
  config :cache_xml_file, :validate => :string, :default => nil

  # The region name
  config :region_name, :validate => :string, :default => "Logstash"

  # A sprintf format to use when building keys
  config :key_format, :validate => :string, :default => "%{@source}-%{@timestamp}"

  public
  def register
    import com.gemstone.gemfire.cache.client.ClientCacheFactory
    import com.gemstone.gemfire.pdx.JSONFormatter

    @logger.info("Registering output", :plugin => self)
    connect
  end # def register

  public
  def connect
    begin
      @logger.debug("Connecting to GemFire #{@name}")

      @cache = ClientCacheFactory.new.
        set("name", @name).
        set("cache-xml-file", @cache_xml_file).create
      @logger.debug("Created cache #{@cache.inspect}")

    rescue => e
      if terminating?
        return
      else
        @logger.error("Gemfire connection error (during connect), will reconnect",
                      :exception => e, :backtrace => e.backtrace)
        sleep(1)
        retry
      end
    end

    @region = @cache.getRegion(@region_name);
    @logger.debug("Created region #{@region.inspect}")
  end # def connect

  public
  def receive(event)
    return unless output?(event)

    @logger.debug("Sending event", :destination => to_s, :event => event)

    key = event.sprintf @key_format

    if @format == "plain"
      message = format_message(event)
    else
      message = JSONFormatter.fromJSON(event.to_json)
    end

    receive_raw(message, key)
  end # def receive

  def self.format_message(event)
    message =  "Date: #{event.timestamp}\n"
    message << "Source: #{event.source}\n"
    message << "Tags: #{event.tags.join(', ')}\n"
    message << "Fields: #{event.fields.inspect}\n"
    message << "Message: #{event.message}"
    message
  end

  public
  def receive_raw(message, key)
    if @region
      @logger.debug(["Publishing message", { :destination => to_s, :message => message, :key => key }])
      @region.put(key, message)
    else
      @logger.warn("Tried to send message, but not connected to GemFire yet.")
    end
  end

  public
  def to_s
    return "gemfire://#{name}"
  end

  public
  def teardown
    @cache.close if @cache
    @cache = nil
    finished
  end # def teardown
end # class LogStash::Outputs::Gemfire
