# Uploads App Store screenshots to the editable App Store version of com.chadjara.jigger.
#
#   ruby asc_screenshots.rb <folder-of-pngs>
#
# Files named iPhone-*.png go to the 6.9" iPhone set (1320 x 2868) and iPad-*.png to the 13" iPad
# set (2064 x 2752 or 2752 x 2064), in file-name order. Each set that receives files is cleared
# first, so a re-run replaces rather than duplicates. Needs ASC_KEY_PATH, ASC_KEY_ID and
# ASC_ISSUER_ID. Never prints the key or the token.
require "digest"
require "json"
require "net/http"
require "openssl"
require "uri"

BUNDLE_ID = "com.chadjara.jigger"
API = "https://api.appstoreconnect.apple.com"
EDITABLE = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
SETS = {
  "iPhone" => { type: "APP_IPHONE_67", sizes: [[1320, 2868]] },
  "iPad" => { type: "APP_IPAD_PRO_3GEN_129", sizes: [[2064, 2752], [2752, 2064]] }
}.freeze

def fail_with(message)
  warn "::error::#{message}"
  exit 1
end

def b64url(bytes)
  [bytes].pack("m0").tr("+/", "-_").delete("=")
end

def token
  return @token if @token && Time.now.to_i < @token_exp - 60
  key = OpenSSL::PKey::EC.new(File.read(ENV.fetch("ASC_KEY_PATH")))
  now = Time.now.to_i
  @token_exp = now + 1200
  header = { alg: "ES256", kid: ENV.fetch("ASC_KEY_ID").strip, typ: "JWT" }
  payload = { iss: ENV.fetch("ASC_ISSUER_ID").strip, iat: now, exp: @token_exp, aud: "appstoreconnect-v1" }
  input = "#{b64url(header.to_json)}.#{b64url(payload.to_json)}"
  der = key.sign(OpenSSL::Digest.new("SHA256"), input)
  r, s = OpenSSL::ASN1.decode(der).value.map { |i| i.value.to_s(2).rjust(32, "\x00".b) }
  @token = "#{input}.#{b64url(r + s)}"
end

def api(method, path, body = nil, query = nil)
  uri = URI(path.start_with?("http") ? path : API + path)
  uri.query = URI.encode_www_form(query) if query
  req = Net::HTTP.const_get(method.capitalize).new(uri)
  req["Authorization"] = "Bearer #{token}"
  if body
    req["Content-Type"] = "application/json"
    req.body = body.to_json
  end
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 60) { |h| h.request(req) }
  unless res.is_a?(Net::HTTPSuccess)
    detail = (JSON.parse(res.body)["errors"] || []).map { |e| e["detail"] || e["title"] }.join("; ") rescue res.body.to_s[0, 300]
    fail_with("App Store Connect #{method.upcase} #{uri.path} returned #{res.code}: #{detail}")
  end
  res.body.to_s.empty? ? {} : JSON.parse(res.body)
end

def png_size(path)
  header = File.binread(path, 24)
  fail_with("#{File.basename(path)} is not a PNG") unless header.start_with?("\x89PNG".b)
  header[16, 8].unpack("NN")
end

folder = ARGV.fetch(0) { fail_with("usage: asc_screenshots.rb <folder>") }
files = Dir[File.join(folder, "*.png")].sort
groups = SETS.keys.to_h { |device| [device, files.select { |f| File.basename(f).start_with?("#{device}-") }] }
groups.reject! { |_, list| list.empty? }
fail_with("No iPhone-*.png or iPad-*.png files in #{folder}") if groups.empty?

groups.each do |device, list|
  fail_with("Apple allows at most 10 #{device} screenshots; found #{list.size}") if list.size > 10
  list.each do |f|
    size = png_size(f)
    unless SETS[device][:sizes].include?(size)
      fail_with("#{File.basename(f)} is #{size.join(' x ')}; the #{device} set needs #{SETS[device][:sizes].map { |s| s.join(' x ') }.join(' or ')}")
    end
  end
end

app = api(:get, "/v1/apps", nil, { "filter[bundleId]" => BUNDLE_ID })["data"].first
fail_with("No App Store Connect app uses #{BUNDLE_ID}") unless app

versions = api(:get, "/v1/apps/#{app['id']}/appStoreVersions", nil, { "filter[platform]" => "IOS", "limit" => "20" })["data"]
version = versions.find { |v| EDITABLE.include?(v.dig("attributes", "appStoreState")) }
fail_with("No editable iOS App Store version (states: #{versions.map { |v| v.dig('attributes', 'appStoreState') }.join(', ')})") unless version
puts "App Store version #{version.dig('attributes', 'versionString')} (#{version.dig('attributes', 'appStoreState')})"

locs = api(:get, "/v1/appStoreVersions/#{version['id']}/appStoreVersionLocalizations")["data"]
loc = locs.find { |l| l.dig("attributes", "locale") == "en-US" } || locs.first
fail_with("The App Store version has no localization yet") unless loc
puts "Localization #{loc.dig('attributes', 'locale')}"

existing_sets = api(:get, "/v1/appStoreVersionLocalizations/#{loc['id']}/appScreenshotSets")["data"]

groups.each do |device, list|
  type = SETS[device][:type]
  set = existing_sets.find { |s| s.dig("attributes", "screenshotDisplayType") == type }
  if set
    old = api(:get, "/v1/appScreenshotSets/#{set['id']}/appScreenshots")["data"]
    old.each { |shot| api(:delete, "/v1/appScreenshots/#{shot['id']}") }
    puts "#{device}: cleared #{old.size} existing screenshot(s)" unless old.empty?
  else
    set = api(:post, "/v1/appScreenshotSets", { data: {
      type: "appScreenshotSets", attributes: { screenshotDisplayType: type },
      relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: loc["id"] } } }
    } })["data"]
  end

  list.each do |path|
    bytes = File.binread(path)
    name = File.basename(path)
    shot = api(:post, "/v1/appScreenshots", { data: {
      type: "appScreenshots", attributes: { fileName: name, fileSize: bytes.bytesize },
      relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set["id"] } } }
    } })["data"]
    shot.dig("attributes", "uploadOperations").each do |op|
      uri = URI(op["url"])
      req = Net::HTTP.const_get(op["method"].capitalize).new(uri)
      (op["requestHeaders"] || []).each { |h| req[h["name"]] = h["value"] }
      req.body = bytes.byteslice(op["offset"], op["length"])
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 120) { |h| h.request(req) }
      fail_with("Uploading #{name} failed with HTTP #{res.code}") unless res.is_a?(Net::HTTPSuccess)
    end
    api(:patch, "/v1/appScreenshots/#{shot['id']}", { data: {
      type: "appScreenshots", id: shot["id"],
      attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(bytes) }
    } })
    state = nil
    30.times do
      state = api(:get, "/v1/appScreenshots/#{shot['id']}")["data"].dig("attributes", "assetDeliveryState", "state")
      break if %w[COMPLETE FAILED].include?(state)
      sleep 2
    end
    fail_with("Apple rejected #{name} (state #{state})") if state == "FAILED"
    puts "#{device}: uploaded #{name} (#{state || 'processing'})"
  end
end

marketing = ENV.fetch("MARKETING_VERSION", "").strip
if !marketing.empty? && version.dig("attributes", "versionString") != marketing
  puts "::warning::The App Store version is #{version.dig('attributes', 'versionString')} but the build is #{marketing}. " \
       "Change it to #{marketing} on the version page so the build can be selected."
end
puts "Done."
