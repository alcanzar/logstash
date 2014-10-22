# encoding: utf-8
require "logstash/json"
require "msgpack"

# pluggable serializer for the persistent queue

class LogStash::JsonSerializer

  # @param event [LogStash::Event] the event to serialize
  # @return [String] the serialized event or nil to skip persistence
  def serialize(event)
    # exclude non LogStash::Event like the LogStash::ShutdownEvent and LogStash::FlushEvent
    event.is_a?(LogStash::Event) ? LogStash::Json.dump(event.to_json_with_metadata) : nil
  end

  # @param data [String] searialized string data to deserialize
  # @return [LogStash::Event] the deserialzed event
  def deserialize(data)
    LogStash::Json.load(data)
  end
end

class LogStash::MessagePackSerializer

  # @param event [LogStash::Event] the event to serialize
  # @return [String] the serialized event or nil to skip persistence
  def serialize(event)
    # exclude non LogStash::Event like the LogStash::ShutdownEvent and LogStash::FlushEvent
    event.is_a?(LogStash::Event) ? MessagePack.pack(event.to_json_with_metadata) : nil
  end

  # @param data [String] searialized string data to deserialize
  # @return [LogStash::Event] the deserialzed event
  def deserialize(data)
    MessagePack.unpack(data)
  end
end

class LogStash::MarshalSerializer

  # @param event [LogStash::Event] the event to serialize
  # @return [String] the serialized event or nil to skip persistence
  def serialize(event)
    # exclude non LogStash::Event like the LogStash::ShutdownEvent and LogStash::FlushEvent
    event.is_a?(LogStash::Event) ? Marshal.dump(event.to_json_with_metadata) : nil
  end

  # @param data [String] searialized string data to deserialize
  # @return [LogStash::Event] the deserialzed event
  def deserialize(data)
    Marshal.load(data)
  end
end
