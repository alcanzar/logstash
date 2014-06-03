# encoding: utf-8
require "logstash/environment"
require "logstash/errors"
if LogStash::Environment.jruby?
  require "jrjackson"
  require "logstash/java_integration"
else
  require  "oj"
end

module LogStash
  module Json
    class ParserError < LogStash::Error; end
    class GeneratorError < LogStash::Error; end

    extend self

    ### MRI

    def mri_load(data)
      Oj.load(data)
    rescue Oj::ParseError => e
      raise LogStash::Json::ParserError.new(e.message)
    end

    def mri_dump(o)
      Oj.dump(o, :mode => :compat, :use_to_json => true)
    rescue => e
      raise LogStash::Json::GeneratorError.new(e.message)
    end

    ### JRuby

    def jruby_load(data)
      JrJackson::Json.load(data, :raw => true)
    rescue JrJackson::ParseError => e
      raise LogStash::Json::ParserError.new(e.message)
    end

    def jruby_dump(o)
      # test for enumerable here to work around an omission in JrJackson::Json.dump to
      # also look for Java::JavaUtil::ArrayList, see TODO submit issue
      o.is_a?(Enumerable) ? JrJackson::Raw.generate(o) : JrJackson::Json.dump(o)
    rescue => e
      raise LogStash::Json::GeneratorError.new(e.message)
    end

    prefix = LogStash::Environment.jruby? ? "jruby" : "mri"
    alias_method :load, "#{prefix}_load".to_sym
    alias_method :dump, "#{prefix}_dump".to_sym

    # recursively convert any java LinkedHashMap and ArrayList to pure Ruby.
    # will no recurse into pure Ruby objects. Pure Ruby object should never
    # contain LinkedHashMap and ArrayList since these are only created at
    # initial deserialization, anything after (deeper) will be pure Ruby.
    def deep_normalize(o)
      case o
      when Java::JavaUtil::LinkedHashMap
        o.inject({}){|r, (k, v)| r[k] = deep_normalize(v); r}
      when Java::JavaUtil::ArrayList
        o.map{|i| deep_normalize(i)}
      else
        o
      end
    end

  end
end
