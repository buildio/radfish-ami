# frozen_string_literal: true

RSpec.describe Radfish::AmiAdapter, "#set_boot_override" do
  let(:adapter) do
    described_class.new(host: "bmc.example.com", username: "admin", password: "secret")
  end
  let(:system_url) { "https://bmc.example.com:443/redfish/v1/Systems/Self" }

  before do
    stub_request(:post, "https://bmc.example.com:443/redfish/v1/SessionService/Sessions")
      .to_return(status: 201, body: { "Id" => "1" }.to_json,
                 headers: { "X-Auth-Token" => "tok",
                            "Location" => "/redfish/v1/SessionService/Sessions/1" })
  end

  def patched_body
    JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys
                 .find { |r| r.method == :patch }.body)["Boot"]
  end

  it "sends target and persistence" do
    stub_request(:patch, system_url).to_return(status: 200, body: "{}")

    expect(adapter.set_boot_override("Cd", persistence: "Once")).to be true
    expect(patched_body).to eq("BootSourceOverrideTarget" => "Cd",
                               "BootSourceOverrideEnabled" => "Once")
  end

  it "sends the mode when one is given" do
    stub_request(:patch, system_url).to_return(status: 200, body: "{}")

    adapter.set_boot_override("Cd", persistence: "Once", mode: "UEFI")

    expect(patched_body).to include("BootSourceOverrideMode" => "UEFI")
  end

  # BMCs without the property reject it outright, so it must stay absent.
  it "omits the mode when none is given" do
    stub_request(:patch, system_url).to_return(status: 200, body: "{}")

    adapter.set_boot_override("Cd", persistence: "Once")

    expect(patched_body).not_to have_key("BootSourceOverrideMode")
  end
end
