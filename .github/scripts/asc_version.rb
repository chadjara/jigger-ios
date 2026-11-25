# Creates the App Store version MARKETING_VERSION for com.chadjara.jigger if there is no editable
# version yet, and attaches the newest valid build of that version once one has been processed.
# Changes no text: App Store Connect copies the description, keywords and screenshots from the
# previous version, and the owner edits wording in App Store Connect.
# Needs ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID and MARKETING_VERSION. Never prints the key or token.
require "json"
require "net/http"
require "openssl"
require "uri"

BUNDLE_ID = "com.chadjara.jigger"
API = "https://api.appstoreconnect.apple.com"
EDITABLE = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
VERSION = ENV.fetch("MARKETING_VERSION").strip

def b64url(bytes) = [bytes].pack("m0").tr("+/", "-_").delete("=")

def token
  return @token if @token
  key = OpenSSL::PKey::EC.new(File.read(ENV.fetch("ASC_KEY_PATH")))
  now = Time.now.to_i
  header = { alg: "ES256", kid: ENV.fetch("ASC_KEY_ID").strip, typ: "JWT" }
  payload = { iss: ENV.fetch("ASC_ISSUER_ID").strip, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" }
  input = "#{b64url(header.to_json)}.#{b64url(payload.to_json)}"
  der = key.sign(OpenSSL::Digest.new("SHA256"), input)
  r, s = OpenSSL::ASN1.decode(der).value.map { |i| i.value.to_s(2).rjust(32, "\x00".b) }
  @token = "#{input}.#{b64url(r + s)}"
end

def api(method, path, body = nil, query = nil)
  uri = URI(API + path)
  uri.query = URI.encode_www_form(query) if query
  req = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
  req["Authorization"] = "Bearer #{token}"
  if body
    req["Content-Type"] = "application/json"
    req.body = body.to_json
  end
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 90) { |h| h.request(req) }
  unless res.is_a?(Net::HTTPSuccess)
    detail = (JSON.parse(res.body)["errors"] || []).map { |e| e["detail"] || e["title"] }.join("; ") rescue res.body.to_s[0, 300]
    abort "::error::#{method.upcase} #{uri.path} returned #{res.code}: #{detail}"
  end
  res.body.to_s.empty? ? {} : JSON.parse(res.body)
end

app = api(:get, "/v1/apps", nil, { "filter[bundleId]" => BUNDLE_ID })["data"].first or abort("::error::app not found")
versions = api(:get, "/v1/apps/#{app['id']}/appStoreVersions", nil, { "filter[platform]" => "IOS", "limit" => "20" })["data"]
puts "## App Store version #{VERSION}\n\n"
versions.each { |v| puts "- #{v.dig('attributes', 'versionString')}: #{v.dig('attributes', 'appStoreState')}" }

version = versions.find { |v| EDITABLE.include?(v.dig("attributes", "appStoreState")) }
if version
  puts "\nEditable version: #{version.dig('attributes', 'versionString')} (#{version.dig('attributes', 'appStoreState')})"
  unless version.dig("attributes", "versionString") == VERSION
    abort "::error::The editable version is #{version.dig('attributes', 'versionString')}, not #{VERSION}. Change one to match."
  end
else
  version = api(:post, "/v1/appStoreVersions", { data: {
    type: "appStoreVersions", attributes: { platform: "IOS", versionString: VERSION },
    relationships: { app: { data: { type: "apps", id: app["id"] } } }
  } })["data"]
  puts "\nCreated version #{VERSION} (#{version.dig('attributes', 'appStoreState')})"
end

builds = api(:get, "/v1/builds", nil, { "filter[app]" => app["id"], "filter[preReleaseVersion.version]" => VERSION,
                                         "filter[processingState]" => "VALID", "sort" => "-uploadedDate", "limit" => "1" })["data"]
if (build = builds.first)
  api(:patch, "/v1/appStoreVersions/#{version['id']}/relationships/build", { data: { type: "builds", id: build["id"] } })
  puts "Build attached: #{VERSION} (#{build.dig('attributes', 'version')})"
else
  puts "No processed #{VERSION} build yet: run this again after the TestFlight upload finishes processing."
end
