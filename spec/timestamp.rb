require "logstash/timestamp"

describe LogStash::Timestamp do

  it "should parse its own iso8601 output" do
    t = Time.now
    ts = LogStash::Timestamp.new(t)
    expect(LogStash::Timestamp.parse_iso8601(ts.to_iso8601).to_i).to eq(t.to_i)
  end

  it "should import iso8601 string" do
    t = Time.now
    ts = LogStash::Timestamp.new(t)
    expect(LogStash::Timestamp.import(ts.to_iso8601).to_i).to eq(t.to_i)
  end

  it "should import Time" do
    t = Time.now
    expect(LogStash::Timestamp.import(t).to_i).to eq(t.to_i)
  end

  it "should import Timestamp" do
    t = LogStash::Timestamp.now
    expect(LogStash::Timestamp.import(t).to_i).to eq(t.to_i)
  end

  it "should raise on invalid string import" do
    expect{LogStash::Timestamp.import("foobar")}.to raise_error LogStash::TimestampParserError
  end

  it "should return nil on invalid object import" do
    expect(LogStash::Timestamp.import(:foobar)).to be_nil
  end

end
