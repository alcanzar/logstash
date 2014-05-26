# encoding: utf-8
require "logstash/environment"
require "logstash/json"
require "forwardable"
require "date"
require "time"

module LogStash

  class Timestamp
    extend Forwardable

    def_delegators :@time, :tv_usec, :usec, :year, :iso8601, :to_i, :tv_sec, :to_f, :to_s, :to_edn

    attr_reader :time

    ISO8601_STRFTIME = "%04d-%02d-%02dT%02d:%02d:%02d.%06d%+03d:00".freeze

    def initialize(time)
      @time = time.nil? ? Time.new.utc : time
    end

    def self.at(*args)
      Timestamp.new(::Time.at(*args))
    end

    def self.parse(*args)
      Timestamp.new(::Time.parse(*args))
    end

    def self.now
      Timestamp.new(::Time.now.utc)
    end

    if LogStash::Environment.jruby?
      JODA_ISO8601_PARSER = org.joda.time.format.ISODateTimeFormat.dateTimeParser
      UTC = org.joda.time.DateTimeZone.forID("UTC")

      def self.parse_iso8601(t)
        millis = JODA_ISO8601_PARSER.parseMillis(t)
        at(millis / 1000, (millis % 1000) * 1000)
      end

    else

      def self.parse_iso8601(t)
        # warning, ruby's Time.parse is *really* terrible and slow.
        t.is_a?(String) ? LogStash::Timestamp.parse(t).gmtime : nil
      end
    end

    def utc
      @time.utc # modifies the receiver
      self
    end
    alias_method :gmtime, :utc

    def to_json
      LogStash::Json.dump(@time.iso8601(3))
    end
    alias_method :inspect, :to_json

  end
end
