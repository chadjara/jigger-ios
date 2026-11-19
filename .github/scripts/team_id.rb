# Prints the Apple Developer Team ID for automatic signing.
# Uses the APPLE_TEAM_ID repository variable when set; otherwise asks the App Store Connect API
# (with the ASC_* key) for the com.chadjara.jigger bundle ID, whose seedId is the team's ID.
# Never prints the key or the token.
require "openssl"
require "json"
require "net/http"
require "uri"

BUNDLE_ID = "com.chadjara.jigger"

def b64url(bytes)
  [bytes].pack("m0").tr("+/", "-_").delete("=")
end

def fail_with(message)
  warn "::error::#{message}"
  exit 1
end

team = ENV.fetch("APPLE_TEAM_ID", "").strip
unless team.empty?
  puts team
  exit 0
end

key_path = ENV.fetch("ASC_KEY_PATH")
key_id = ENV.fetch("ASC_KEY_ID", "").strip
issuer = ENV.fetch("ASC_ISSUER_ID", "").strip
fail_with("ASC_KEY_ID or ASC_ISSUER_ID secret is missing.") if key_id.empty? || issuer.empty?

begin
  key = OpenSSL::PKey::EC.new(File.read(key_path))
rescue StandardError
  fail_with("ASC_KEY_P8 is not a valid App Store Connect .p8 key (paste the whole file, including the BEGIN/END lines).")
end

now = Time.now.to_i
header = { alg: "ES256", kid: key_id, typ: "JWT" }
payload = { iss: issuer, iat: now, exp: now + 600, aud: "appstoreconnect-v1" }
signing_input = "#{b64url(header.to_json)}.#{b64url(payload.to_json)}"
der = key.sign(OpenSSL::Digest.new("SHA256"), signing_input)
# JWT wants the raw 64-byte r||s signature, not DER.
r, s = OpenSSL::ASN1.decode(der).value.map { |i| i.value.to_s(2).rjust(32, "\x00".b) }
token = "#{signing_input}.#{b64url(r + s)}"

uri = URI("https://api.appstoreconnect.apple.com/v1/bundleIds")
uri.query = URI.encode_www_form("filter[identifier]" => BUNDLE_ID, "limit" => "200")
request = Net::HTTP::Get.new(uri)
request["Authorization"] = "Bearer #{token}"
begin
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 30) { |http| http.request(request) }
rescue StandardError => e
  fail_with("Couldn't reach the App Store Connect API (#{e.class}). Set a repository variable APPLE_TEAM_ID to skip this lookup.")
end
unless response.is_a?(Net::HTTPSuccess)
  fail_with("App Store Connect API returned #{response.code} while looking up the team ID. " \
            "Check the ASC_* secrets, or set a repository variable APPLE_TEAM_ID.")
end

item = JSON.parse(response.body).fetch("data", []).find { |b| b.dig("attributes", "identifier") == BUNDLE_ID }
team = item&.dig("attributes", "seedId").to_s
fail_with("Bundle ID #{BUNDLE_ID} was not found for this API key's team. Set a repository variable APPLE_TEAM_ID.") if team.empty?
puts team
