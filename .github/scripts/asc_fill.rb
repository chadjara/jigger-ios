# Fills in App Store Connect items for com.chadjara.jigger from docs/app-store/metadata.json:
# content rights, price, availability, version number (MARKETING_VERSION), copyright, description,
# keywords, promotional text, support URL, review notes, and attaches the newest valid build of
# that version. Never touches the review contact name, phone or email. Each step is independent:
# one failing doesn't stop the rest. Needs ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID.
require "json"
require "net/http"
require "openssl"
require "uri"

BUNDLE_ID = "com.chadjara.jigger"
API = "https://api.appstoreconnect.apple.com"
EDITABLE = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
META = JSON.parse(File.read(ARGV.fetch(0, "docs/app-store/metadata.json")))
VERSION = ENV.fetch("MARKETING_VERSION").strip

class ApiError < StandardError; end

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

def api(method, path, body = nil, query = nil, allow404: false)
  uri = URI(API + path)
  uri.query = URI.encode_www_form(query) if query
  req = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
  req["Authorization"] = "Bearer #{token}"
  if body
    req["Content-Type"] = "application/json"
    req.body = body.to_json
  end
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 90) { |h| h.request(req) }
  return nil if allow404 && res.code == "404"
  unless res.is_a?(Net::HTTPSuccess)
    detail = (JSON.parse(res.body)["errors"] || []).map { |e| e["detail"] || e["title"] }.join("; ") rescue res.body.to_s[0, 300]
    raise ApiError, "#{method.upcase} #{uri.path} → #{res.code}: #{detail}"
  end
  res.body.to_s.empty? ? {} : JSON.parse(res.body)
end

$failed = []
def step(name)
  result = yield
  puts "✅ #{name}#{result.is_a?(String) ? " — #{result}" : ''}"
rescue StandardError => e
  puts "❌ #{name} — #{e.message}"
  $failed << name
end

app = api(:get, "/v1/apps", nil, { "filter[bundleId]" => BUNDLE_ID })["data"].first or abort("::error::app not found")
versions = api(:get, "/v1/apps/#{app['id']}/appStoreVersions", nil, { "filter[platform]" => "IOS", "limit" => "20" })["data"]
version = versions.find { |v| EDITABLE.include?(v.dig("attributes", "appStoreState")) } or abort("::error::no editable iOS version")
puts "## Filling App Store Connect for #{app.dig('attributes', 'name')} #{version.dig('attributes', 'versionString')}\n\n"

step("Content rights") do
  api(:patch, "/v1/apps/#{app['id']}", { data: { type: "apps", id: app["id"],
    attributes: { contentRightsDeclaration: META.fetch("contentRights") } } })
  META["contentRights"]
end

step("Version number and copyright") do
  api(:patch, "/v1/appStoreVersions/#{version['id']}", { data: { type: "appStoreVersions", id: version["id"],
    attributes: { versionString: VERSION, copyright: META.fetch("copyright") } } })
  "#{VERSION}, © #{META['copyright']}"
end

step("Build attached") do
  builds = api(:get, "/v1/builds", nil, { "filter[app]" => app["id"], "filter[preReleaseVersion.version]" => VERSION,
                                           "filter[processingState]" => "VALID", "sort" => "-uploadedDate", "limit" => "1" })["data"]
  build = builds.first or raise ApiError, "no processed build of #{VERSION} found"
  api(:patch, "/v1/appStoreVersions/#{version['id']}/relationships/build", { data: { type: "builds", id: build["id"] } })
  "#{VERSION} (#{build.dig('attributes', 'version')})"
end

step("Description, keywords, promotional text, support URL") do
  locs = api(:get, "/v1/appStoreVersions/#{version['id']}/appStoreVersionLocalizations")["data"]
  loc = locs.find { |l| l.dig("attributes", "locale") == "en-US" } || locs.first or raise ApiError, "no version localization"
  api(:patch, "/v1/appStoreVersionLocalizations/#{loc['id']}", { data: { type: "appStoreVersionLocalizations", id: loc["id"],
    attributes: { description: META.fetch("description"), keywords: META.fetch("keywords"),
                  promotionalText: META.fetch("promotionalText"), supportUrl: META.fetch("supportUrl") } } })
  "#{META['description'].length}-character description, #{META['keywords'].split(',').size} keywords"
end

step("Review notes (sign-in not required)") do
  detail = api(:get, "/v1/appStoreVersions/#{version['id']}/appStoreReviewDetail", allow404: true)&.dig("data")
  attrs = { notes: META.fetch("reviewNotes"), demoAccountRequired: false }
  if detail
    api(:patch, "/v1/appStoreReviewDetails/#{detail['id']}", { data: { type: "appStoreReviewDetails", id: detail["id"], attributes: attrs } })
  else
    api(:post, "/v1/appStoreReviewDetails", { data: { type: "appStoreReviewDetails", attributes: attrs,
      relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version["id"] } } } } })
  end
  "contact name, phone and email left for you"
end

step("Price") do
  existing = api(:get, "/v1/apps/#{app['id']}/appPriceSchedule", allow404: true)&.dig("data")
  if existing && (api(:get, "/v1/appPriceSchedules/#{existing['id']}/manualPrices", nil, { "limit" => "1" }, allow404: true)&.dig("data") || []).any?
    next "already set"
  end
  raise ApiError, "metadata.json price must be \"free\"" unless META["price"] == "free"
  points = api(:get, "/v1/apps/#{app['id']}/appPricePoints", nil, { "filter[territory]" => "USA", "limit" => "200" })["data"]
  free = points.find { |p| p.dig("attributes", "customerPrice").to_f.zero? } or raise ApiError, "no free price point"
  api(:post, "/v1/appPriceSchedules", {
    data: { type: "appPriceSchedules", relationships: {
      app: { data: { type: "apps", id: app["id"] } },
      baseTerritory: { data: { type: "territories", id: "USA" } },
      manualPrices: { data: [{ type: "appPrices", id: "${free}" }] } } },
    included: [{ type: "appPrices", id: "${free}", attributes: { startDate: nil },
                 relationships: { appPricePoint: { data: { type: "appPricePoints", id: free["id"] } } } }] })
  "Free"
end

step("Availability") do
  if api(:get, "/v1/apps/#{app['id']}/appAvailabilityV2", allow404: true)&.dig("data")
    next "already set"
  end
  excluded = META.fetch("excludeTerritories", [])
  territories = api(:get, "/v1/territories", nil, { "limit" => "200" })["data"].map { |t| t["id"] } - excluded
  api(:post, "/v2/appAvailabilities", {
    data: { type: "appAvailabilities", attributes: { availableInNewTerritories: true }, relationships: {
      app: { data: { type: "apps", id: app["id"] } },
      territoryAvailabilities: { data: territories.map { |t| { type: "territoryAvailabilities", id: "${#{t}}" } } } } },
    included: territories.map { |t| { type: "territoryAvailabilities", id: "${#{t}}", attributes: { available: true },
                                      relationships: { territory: { data: { type: "territories", id: t } } } } } })
  "#{territories.size} countries and regions#{excluded.empty? ? '' : " (not #{excluded.join(', ')})"}"
end

puts "\n#{$failed.empty? ? 'All steps done.' : "#{$failed.size} step(s) failed: #{$failed.join(', ')}"}"
exit($failed.empty? ? 0 : 1)
