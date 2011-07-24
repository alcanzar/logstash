require "logstash/outputs/base"
require "logstash/namespace"

# TODO(sissel): Document what statsd is and where to learn about it
# Also document an example.
class LogStash::Outputs::Statsd < LogStash::Outputs::Base
  # Regex stolen from statsd code
  RESERVED_CHARACTERS_REGEX = /[\.\:\|\@]/
  config_name "statsd"

  # The address of the Statsd server.
  config :host, :validate => :string, :default => "localhost"

  # The port to connect to on your statsd server.
  config :port, :validate => :number, :default => 8125

  # The statsd namespace to use for this metric
  config :namespace, :validate => :string, :default => "logstash"

  # The name of the sender.
  # Dots will be replaced with underscores
  config :sender, :validate => :string, :default => "%{@source_host}"

  # An increment metric. metric names as array.
  config :increment, :validate => :array, :default => []

  # A decrement metric. metric names as array.
  config :decrement, :validate => :array, :default => []

  # A timing metric. metric_name => duration as hash
  config :timing, :validate => :hash, :default => {}

  # A count metric. metric_name => count as hash
  config :count, :validate => :hash, :default => {}

  # The sample rate for the metric
  config :sample_rate, :validate => :number, :default => 1

  # Only handle these tagged events
  # Optional.
  config :tags, :validate => :array, :default => []

  # The final metric sent to statsd will look like the following (assuming defaults)
  # logstash.sender.file_name
  #
  # Enable debugging output?
  config :debug, :validate => :boolean, :default => false

  public
  def register
    require "statsd"
    @client = Statsd.new(@host, @port)
  end # def register

  public
  def receive(event)
    if !@tags.empty?
      if (event.tags - @tags).size == 0
        return
      end
    end

    @client.namespace = event.sprintf(@namespace)
    logger.debug("Original sender: #{@sender}")
    @sender = event.sprintf(@sender)
    logger.debug("Munged sender: #{@sender}")
    logger.debug("Event: #{event}")
    @increment.each do |metric|
      @client.increment(build_stat(event.sprintf(metric)), @sample_rate)
    end
    @decrement.each do |metric|
      @client.decrement(build_stat(event.sprintf(metric)), @sample_rate)
    end
    @count.each do |metric, val|
      @client.count(build_stat(event.sprintf(metric)), 
                    event.sprintf(val).to_f, @sample_rate)
    end
    @timing.each do |metric, val|
      @client.timing(build_stat(event.sprintf(metric)),
                     event.sprintf(val).to_f, @sample_rate)
    end
  end # def receive

  def build_stat(metric, sender=@sender)
    sender = sender.gsub('::','.').gsub(RESERVED_CHARACTERS_REGEX, '_').gsub(".", "_")
    metric = metric.gsub('::','.').gsub(RESERVED_CHARACTERS_REGEX, '_')
    @logger.debug("Formatted sender: #{sender}")
    @logger.debug("Formatted metric: #{metric}")
    return "#{sender}.#{metric}"
  end
end # class LogStash::Outputs::Statsd
