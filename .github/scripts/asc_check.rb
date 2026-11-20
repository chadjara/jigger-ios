# Read-only App Store submission check for com.chadjara.jigger. Changes nothing.
#
# Lists what App Store Connect still needs before "Add for Review" works. The repository is
# public, so personal details (review contact name, phone, email, notes) are reported only as
# set or missing, never printed. Needs ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID.
require "json"
require "net/http"
require "openssl"
require "uri"

BUNDLE_ID = "com.chadjara.jigger"
API = "https://api.appstoreconnect.apple.com"
EDITABLE = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
EXPECTED_VERSION = ENV.fetch("MARKETING_VERSION", "").strip

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

# GET that returns nil (instead of failing) when the resource doesn't exist yet.
def get(path, query = nil)
  uri = URI(API + path)
  uri.query = URI.encode_www_form(query) if query
  req = Net::HTTP::Get.new(uri)
  req["Authorization"] = "Bearer #{token}"
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 60) { |h| h.request(req) }
  return nil if res.code == "404"
  unless res.is_a?(Net::HTTPSuccess)
    warn "::warning::GET #{uri.path} returned #{res.code}"
    return nil
  end
  JSON.parse(res.body)
end

$problems = []
def ok(label, detail = nil) = puts("✅ #{label}#{detail ? " — #{detail}" : ''}")
def bad(label, fix)
  puts "❌ #{label} — #{fix}"
  $problems << label
end
def check(cond, label, detail, fix) = cond ? ok(label, detail) : bad(label, fix)
def present?(v) = !v.nil? && !v.to_s.strip.empty?

app = get("/v1/apps", { "filter[bundleId]" => BUNDLE_ID })&.dig("data", 0)
abort("::error::No App Store Connect app uses #{BUNDLE_ID}") unless app
a = app["attributes"]
puts "## App Store submission check: #{a['name']}\n\n"

puts "### App Information"
check(present?(a["contentRightsDeclaration"]), "Content rights", a["contentRightsDeclaration"],
      "App Information → Content Rights: answer the question")
infos = get("/v1/apps/#{app['id']}/appInfos")&.dig("data") || []
info = infos.find { |i| i.dig("attributes", "state") != "READY_FOR_DISTRIBUTION" } || infos.first
if info
  loc = get("/v1/appInfos/#{info['id']}/appInfoLocalizations")&.dig("data")&.find { |l| l.dig("attributes", "locale") == "en-US" }
  la = loc&.dig("attributes") || {}
  check(present?(la["name"]), "Name", la["name"], "App Information → Name")
  check(present?(la["subtitle"]), "Subtitle", la["subtitle"], "App Information → Subtitle: Drink cost & menu pricing")
  check(present?(la["privacyPolicyUrl"]), "Privacy Policy URL", la["privacyPolicyUrl"], "App Privacy → Privacy Policy URL")
  primary = get("/v1/appInfos/#{info['id']}/primaryCategory")&.dig("data", "id")
  secondary = get("/v1/appInfos/#{info['id']}/secondaryCategory")&.dig("data", "id")
  check(present?(primary), "Primary category", primary, "App Information → Category: Food & Drink")
  puts(present?(secondary) ? "✅ Secondary category — #{secondary}" : "➖ Secondary category — not set (optional; suggested: Business)")
  age = get("/v1/appInfos/#{info['id']}/ageRatingDeclaration")&.dig("data", "attributes") || {}
  answered = age.values.compact.size
  check(answered > 0, "Age rating questionnaire",
        "alcohol/tobacco/drugs: #{age['alcoholTobaccoOrDrugUseOrReferences'] || 'unanswered'}; rating #{info.dig('attributes', 'appStoreAgeRating') || 'pending'}",
        "App Information → Age Rating: complete the questionnaire")
else
  bad("App Information", "no app info record found")
end

puts "\n### Pricing and Availability"
sched = get("/v1/apps/#{app['id']}/appPriceSchedule")&.dig("data")
if sched
  prices = get("/v1/appPriceSchedules/#{sched['id']}/manualPrices", { "include" => "appPricePoint", "limit" => "5" })
  price = prices&.dig("included")&.find { |i| i["type"] == "appPricePoints" }&.dig("attributes", "customerPrice")
  check(!price.nil?, "Price", price.nil? ? nil : (price.to_f.zero? ? "Free" : price), "Pricing and Availability → set the price (Free)")
else
  bad("Price", "Pricing and Availability → set the price (Free)")
end
avail = get("/v1/apps/#{app['id']}/appAvailabilityV2")&.dig("data")
if avail
  terr = get("/v2/appAvailabilities/#{avail['id']}/territoryAvailabilities", { "limit" => "200" })&.dig("data") || []
  on = terr.count { |t| t.dig("attributes", "available") }
  check(on > 0, "Availability", "#{on} countries or regions", "Pricing and Availability → choose countries")
else
  bad("Availability", "Pricing and Availability → choose countries or regions")
end

puts "\n### iOS App version"
versions = get("/v1/apps/#{app['id']}/appStoreVersions", { "filter[platform]" => "IOS", "limit" => "20" })&.dig("data") || []
version = versions.find { |v| EDITABLE.include?(v.dig("attributes", "appStoreState")) }
abort("::error::No editable iOS version (#{versions.map { |v| v.dig('attributes', 'appStoreState') }.join(', ')})") unless version
va = version["attributes"]
check(EXPECTED_VERSION.empty? || va["versionString"] == EXPECTED_VERSION, "Version number", va["versionString"],
      "version page → change #{va['versionString']} to #{EXPECTED_VERSION} (must match the build)")
check(present?(va["copyright"]), "Copyright", va["copyright"], "version page → Copyright, e.g. 2026 your name")
ok("Release option", va["releaseType"]) if va["releaseType"]

vloc = get("/v1/appStoreVersions/#{version['id']}/appStoreVersionLocalizations")&.dig("data")&.find { |l| l.dig("attributes", "locale") == "en-US" }
vl = vloc&.dig("attributes") || {}
check(present?(vl["description"]), "Description", present?(vl["description"]) ? "#{vl['description'].length} characters" : nil, "version page → Description")
check(present?(vl["keywords"]), "Keywords", vl["keywords"], "version page → Keywords")
check(present?(vl["supportUrl"]), "Support URL", vl["supportUrl"], "version page → Support URL")
puts(present?(vl["promotionalText"]) ? "✅ Promotional text — set" : "➖ Promotional text — not set (optional)")
puts(present?(vl["marketingUrl"]) ? "✅ Marketing URL — #{vl['marketingUrl']}" : "➖ Marketing URL — not set (optional)")

if vloc
  sets = get("/v1/appStoreVersionLocalizations/#{vloc['id']}/appScreenshotSets")&.dig("data") || []
  counts = sets.to_h do |s|
    [s.dig("attributes", "screenshotDisplayType"), (get("/v1/appScreenshotSets/#{s['id']}/appScreenshots")&.dig("data") || []).size]
  end
  check(counts.fetch("APP_IPHONE_67", 0) > 0, "iPhone 6.9\" screenshots", "#{counts.fetch('APP_IPHONE_67', 0)}", "upload iPhone screenshots")
  check(counts.fetch("APP_IPAD_PRO_3GEN_129", 0) > 0, "iPad 13\" screenshots", "#{counts.fetch('APP_IPAD_PRO_3GEN_129', 0)}", "upload iPad screenshots")
  others = counts.reject { |k, _| %w[APP_IPHONE_67 APP_IPAD_PRO_3GEN_129].include?(k) }
  puts "ℹ️ Other screenshot sets: #{others.map { |k, v| "#{k} (#{v})" }.join(', ')}" unless others.empty?
end

build = get("/v1/appStoreVersions/#{version['id']}/build")&.dig("data")
if build
  ba = build["attributes"]
  ok("Build attached", "#{EXPECTED_VERSION} (#{ba['version']}), #{ba['processingState']}")
  check(ba["usesNonExemptEncryption"] == false || ba["usesNonExemptEncryption"].nil?, "Export compliance",
        "no non-exempt encryption", "answer the encryption question for the build")
else
  latest = get("/v1/builds", { "filter[app]" => app["id"], "sort" => "-uploadedDate", "limit" => "3" })&.dig("data") || []
  names = latest.map { |b| "#{b.dig('attributes', 'version')} (#{b.dig('attributes', 'processingState')})" }.join(", ")
  bad("Build attached", "version page → Build → Add Build, choose the newest: #{names}")
end

review = get("/v1/appStoreVersions/#{version['id']}/appStoreReviewDetail")&.dig("data", "attributes")
if review
  { "contactFirstName" => "Review contact first name", "contactLastName" => "Review contact last name",
    "contactPhone" => "Review contact phone", "contactEmail" => "Review contact email" }.each do |f, label|
    check(present?(review[f]), label, "set", "version page → App Review Information → #{label}")
  end
  check(review["demoAccountRequired"] != true, "Sign-in required", "off", "turn off 'Sign-in required' (the app has no accounts)")
  puts(present?(review["notes"]) ? "✅ Review notes — set" : "➖ Review notes — not set (recommended)")
else
  bad("App Review Information", "version page → App Review Information: contact name, phone, email")
end

puts "\n### Not readable through Apple's API (check by eye)"
puts "- App Privacy: the questionnaire must be **published** (Data Not Collected)."
puts "- Digital Services Act trader status (EU): declared."
puts "\n#{$problems.empty? ? '**Everything Apple checks through the API is ready.**' : "**#{$problems.size} item(s) to fix:** #{$problems.join(', ')}"}"
