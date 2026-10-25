#!/usr/bin/env ruby

require "json"
require "net/http"
require "open3"
require "optparse"
require "uri"

BASE = "https://personal.connectapi.garmin.com"

ntfy_topic = nil
options = OptionParser.new do |parser|
  parser.banner = "Usage: #{File.basename($PROGRAM_NAME)} [--ntfy-topic TOPIC]"
  parser.on("--ntfy-topic TOPIC", "Send low-battery alerts to this ntfy.sh topic") do |topic|
    topic = topic.strip
    abort "ntfy topic is empty; supply --ntfy-topic TOPIC" if topic.empty?
    abort "ntfy topic must be a topic name, without a URL, containing only letters, numbers, underscores, or hyphens" unless topic.match?(/\A[A-Za-z0-9_-]+\z/)
    ntfy_topic = topic
  end
end
begin
  options.parse!
  abort options.to_s unless ARGV.empty?
rescue OptionParser::ParseError => e
  abort "#{e.message}\n#{options}"
end

def request(path, token: nil, api_key: nil)
  uri = URI("#{BASE}#{path}")
  req = if api_key
          Net::HTTP::Post.new(uri)
        else
          Net::HTTP::Get.new(uri)
        end
  req["Authorization"] = api_key ? "ApiKey #{api_key}" : "Bearer #{token}"
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 30
  response = http.request(req)
  abort "API returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  response.body
end

begin
  key = ENV["GARMIN_API_KEY"]
  if key.nil?
    key, status = Open3.capture2("gopass", "show", "external/garmin")
    abort "Could not read external/garmin from gopass" unless status.success?
  end
abort "GARMIN_API_KEY must not be empty" if key.strip.empty?

token = request("/personalapitoken-service/personal-api/personal-api-key/token", api_key: key.strip)
activities = JSON.parse(request("/activitylist-service/activities/search/activities?start=0&limit=1", token: token))
abort "No Garmin activities found" if activities.empty?

activity = activities.first
details = JSON.parse(request("/activity-service/activity/#{activity.fetch('activityId')}", token: token))
sensors = details.dig("metadataDTO", "sensors") || []
low_sensors = sensors.select { |sensor| sensor["batteryStatus"] == "LOW" }

puts "#{activity.fetch('activityName')} (#{activity.fetch('startTimeLocal')})"
if sensors.empty?
  puts "No sensor hardware data recorded."
else
  sensors.each do |sensor|
    type = if sensor["manufacturer"] == "SHIMANO"
             "Pedals"
           else
             sensor["antplusDeviceType"] || sensor["bleDeviceType"] || "device"
           end
    connection = { "ANTPLUS" => "ANT+", "BLUETOOTH_LOW_ENERGY" => "Bluetooth LE", "ANT" => "ANT" }
    connection = connection.fetch(sensor["sourceType"], sensor["sourceType"] || "connection unknown")
    battery = [sensor["batteryStatus"], sensor["batteryLevel"] && "#{sensor['batteryLevel']}%"].compact.join(", ")
    puts "#{sensor['manufacturer']} #{type} (#{connection}): #{battery.empty? ? 'battery data unavailable' : battery}"
  end
end

if ntfy_topic
  if low_sensors.empty?
    puts "No low-battery sensors; nothing sent."
  else
    date_time = activity.fetch("startTimeLocal")
    alerts = low_sensors.map do |sensor|
      type = sensor["manufacturer"] == "SHIMANO" ? "Pedals" : sensor["antplusDeviceType"] || sensor["bleDeviceType"] || "device"
      level = sensor["batteryLevel"] ? " #{sensor['batteryLevel']}%" : ""
      "#{sensor['manufacturer']} #{type} LOW#{level}"
    end
    uri = URI("https://ntfy.sh/#{ntfy_topic}")
    response = Net::HTTP.post(uri, "#{date_time} | #{alerts.join(', ')}", "Content-Type" => "text/plain", "Title" => "🔺🔺 Garmin low battery")
    abort "ntfy returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    puts "Sent low-battery notification."
  end
end
rescue JSON::ParserError => e
  abort "Could not parse Garmin API response: #{e.message}"
rescue KeyError => e
  abort "Garmin response is missing expected field: #{e.message}"
end
