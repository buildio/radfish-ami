# frozen_string_literal: true

# Load the adapter compliance shared examples
require_relative '../support/adapter_compliance'

RSpec.describe Radfish::AmiAdapter do
  let(:adapter) do
    described_class.new(
      host: "bmc.example.com",
      username: "admin",
      password: "secret"
    )
  end

  # Test adapter interface compliance
  it_behaves_like "a radfish adapter"

  describe "#vendor" do
    it "returns 'ami'" do
      expect(adapter.vendor).to eq("ami")
    end
  end

  describe "adapter registration" do
    it "is registered as 'ami'" do
      expect(Radfish.get_adapter("ami")).to eq(described_class)
    end

    it "is also registered as 'asrockrack'" do
      expect(Radfish.get_adapter("asrockrack")).to eq(described_class)
    end
  end

  describe "#login" do
    before do
      stub_request(:post, "https://bmc.example.com:443/redfish/v1/SessionService/Sessions")
        .to_return(
          status: 201,
          headers: {
            "X-Auth-Token" => "test-token-123",
            "Location" => "/redfish/v1/SessionService/Sessions/1"
          },
          body: { "Id" => "1" }.to_json
        )
    end

    it "creates a session successfully" do
      expect(adapter.login).to be true
    end
  end

  describe "#power_status" do
    before do
      stub_request(:post, "https://bmc.example.com:443/redfish/v1/SessionService/Sessions")
        .to_return(
          status: 201,
          headers: { "X-Auth-Token" => "test-token" },
          body: { "Id" => "1" }.to_json
        )

      stub_request(:get, "https://bmc.example.com:443/redfish/v1/Systems/Self")
        .to_return(
          status: 200,
          body: { "PowerState" => "On" }.to_json
        )

      adapter.login
    end

    it "returns the power state" do
      expect(adapter.power_status).to eq("On")
    end
  end

  describe "#system_info" do
    let(:system_response) do
      {
        "Manufacturer" => "ASRockRack",
        "Model" => "GENOAD8UD-2T/X550",
        "SerialNumber" => "J4S0R8000193",
        "PowerState" => "On"
      }
    end

    before do
      stub_request(:post, "https://bmc.example.com:443/redfish/v1/SessionService/Sessions")
        .to_return(
          status: 201,
          headers: { "X-Auth-Token" => "test-token" },
          body: { "Id" => "1" }.to_json
        )

      stub_request(:get, "https://bmc.example.com:443/redfish/v1/Systems/Self")
        .to_return(status: 200, body: system_response.to_json)

      adapter.login
    end

    it "returns system information" do
      info = adapter.system_info
      expect(info["Manufacturer"]).to eq("ASRockRack")
      expect(info["Model"]).to eq("GENOAD8UD-2T/X550")
    end

    it "extracts make" do
      expect(adapter.make).to eq("ASRockRack")
    end

    it "extracts model" do
      expect(adapter.model).to eq("GENOAD8UD-2T/X550")
    end

    it "extracts serial" do
      expect(adapter.serial).to eq("J4S0R8000193")
    end
  end
end
