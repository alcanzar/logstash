require "date"
require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/time" # should really use the filters/date.rb bits

require "mysql2"
require "php_serialize"

# Read messages as events over the network via udp.
#
class LogStash::Inputs::DrupalDblog < LogStash::Inputs::Base
  config_name "drupal_dblog"
  plugin_status "experimental"



  # The database host
  config :host, :validate => :string, :required => true

  # Mysql database port
  config :port, :validate => :number, :default => 3306

  # Database name
  config :database, :validate => :string, :required => true

  # Database password
  config :user, :validate => :string, :required => true

  # Database password
  config :password, :validate => :string, :required => true

  # Name of the Drupal site, used for event source
  config :sitename, :validate => :string, :default => ""

  # Add the username in addition to the user id to the event
  config :add_usernames, :validate => :boolean, :default => false

  # Time between checks in minutes
  config :interval, :validate => :number, :default => 10

  public
  def initialize(params)
    super
    @format = "json_event"
    @debug = true
  end # def initialize

  public
  def register

  end # def register

  public
  def run(output_queue)
    @logger.info("Initializing drupal_dblog", :database => @database)

    loop do
      @logger.debug("Starting to fetch new watchdog entries")
      start = Time.now.to_i
      check_database(output_queue)

      timeTaken = Time.now.to_i - start
      sleepTime = @interval * 1 - timeTaken
      @logger.debug("Fetched all new watchdog entries. Sleeping for " + sleepTime.to_s + " seconds")
      sleep(sleepTime)
    end # loop
  end # def run

  private
  def check_database(output_queue)

    begin
      # connect to the MySQL server
      @client = Mysql2::Client.new(
        :host => @host,
        :port => @port,
        :username => @user,
        :password => @password,
        :database => @database
      )

      # If no source is set, try to retrieve site name.
      update_sitename

      @usermap = @add_usernames ? get_usermap : nil

      # Retrieve last pulled watchdog entry id
      initialLastWid = get_last_wid
      lastWid = initialLastWid ? initialLastWid : "0"

      # Fetch new entries, and create the event
      results = @client.query('SELECT * from watchdog WHERE wid > ' + initialLastWid + " ORDER BY wid asc")
      results.each do |row|
        event = build_event(row)
        if event
          output_queue << to_event(JSON.dump(event), "")
          lastWid = row['wid'].to_s
        end
      end

      set_last_wid(lastWid, initialLastWid == false)
    rescue Mysql2::Error => e
      @logger.info("Mysql error: ", :error => e.error)
    end # begin

    # Close connection
    @client.close
  end # def get_net_entries

  private
  def update_sitename
    if @sitename == ""
      result = @client.query('SELECT value FROM variable WHERE name="site_name"')
      if result.first()
        @sitename = PHP.unserialize(result.first()['value'])
      end
    end
  end

  private
  def get_last_wid
    result = @client.query('SELECT value FROM variable WHERE name="logstash_last_wid"')
    lastWid = false

    if result.count() > 0
      tmp = result.first()["value"].gsub("i:", "").gsub(";", "")
      lastWid = tmp.to_i.to_s == tmp ? tmp : "0"
    end

    return lastWid
  end

  private
  def set_last_wid(wid, insert)
    # Update last import wid variable
    if insert
      # Does not exist yet, so insert
      @client.query('INSERT INTO variable (name, value) VALUES("logstash_last_wid", "' + wid + '")')
    else
      @client.query('UPDATE variable SET value="' + wid + '" WHERE name="logstash_last_wid"')
    end
  end

  private
  def get_usermap
    map = {}

    @client.query("SELECT uid, name FROM users").each do |row|
      map[row["uid"]] = row["name"]
    end

    map[0] = "guest"
    return map
  end

  private
  def build_event(row)
    # Convert unix timestamp
    timestamp = Time.at(row["timestamp"]).to_datetime.iso8601

    msg = row["message"]
    vars = {}

    # Unserialize the variables, and construct the message
    if row['variables'] != 'N;'
      vars = PHP.unserialize(row["variables"])

      if vars.is_a?(Hash)
        vars.each_pair do |k, v|
          if msg.scan(k).length() > 0
            msg = msg.gsub(k.to_s, v.to_s)
          else
            # If not inside the message, add var as an additional field
            row["variable_" + k] = v
          end
        end
      end
    end

    row.delete("message")
    row.delete("variables")
    row.delete("timestamp")

    if @add_usernames and @usermap.has_key?(row["uid"])
      row["user"] = @usermap[row["uid"]]
    end

    entry = {
      "@timestamp" => timestamp,
      "@tags" => [],
      "@type" => "watchdog",
      "@source" => @sitename,
      "@fields" => row,
      "@message" => msg
    }

    return entry
  end # def build_event

end # class LogStash::Inputs::DrupalDblog
