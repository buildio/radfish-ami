# frozen_string_literal: true

# Adapter compliance shared examples for radfish adapters.
# This can be loaded from radfish gem or defined locally.

# Try to load from radfish gem first
begin
  require 'radfish/spec/adapter_compliance'
rescue LoadError
  # Define inline if radfish gem doesn't have it yet
end

# Define shared examples if not already defined
unless RSpec.world.shared_example_group_registry.find([:main], "a radfish adapter")

  RSpec.shared_examples "a radfish adapter" do
    # Core requirements
    describe "adapter interface" do
      it "responds to vendor" do
        expect(adapter).to respond_to(:vendor)
      end

      it "returns a string vendor name" do
        expect(adapter.vendor).to be_a(String)
      end

      it "responds to adapter (for self-reference compatibility)" do
        expect(adapter).to respond_to(:adapter)
      end
    end

    # Session management
    describe "session management" do
      it { expect(adapter).to respond_to(:login) }
      it { expect(adapter).to respond_to(:logout) }
      it { expect(adapter).to respond_to(:authenticated_request) }
    end

    # Power management (Core::Power)
    describe "power management" do
      it { expect(adapter).to respond_to(:power_status) }
      it { expect(adapter).to respond_to(:power_on) }
      it { expect(adapter).to respond_to(:power_off) }
      it { expect(adapter).to respond_to(:power_restart) }
      it { expect(adapter).to respond_to(:power_cycle) }
      it { expect(adapter).to respond_to(:reset_type_allowed) }
    end

    # System information (Core::System)
    describe "system information" do
      it { expect(adapter).to respond_to(:system_info) }
      it { expect(adapter).to respond_to(:service_tag) }
      it { expect(adapter).to respond_to(:make) }
      it { expect(adapter).to respond_to(:model) }
      it { expect(adapter).to respond_to(:serial) }
      it { expect(adapter).to respond_to(:cpus) }
      it { expect(adapter).to respond_to(:memory) }
      it { expect(adapter).to respond_to(:nics) }
      it { expect(adapter).to respond_to(:fans) }
      it { expect(adapter).to respond_to(:temperatures) }
      it { expect(adapter).to respond_to(:psus) }
      it { expect(adapter).to respond_to(:power_consumption) }
      it { expect(adapter).to respond_to(:power_consumption_watts) }
    end

    # Storage (Core::Storage)
    describe "storage" do
      it { expect(adapter).to respond_to(:storage_controllers) }
      it { expect(adapter).to respond_to(:drives) }
      it { expect(adapter).to respond_to(:volumes) }
      it { expect(adapter).to respond_to(:storage_summary) }
      it { expect(adapter).to respond_to(:volume_drives) }
    end

    # Virtual Media (Core::VirtualMedia)
    describe "virtual media" do
      it { expect(adapter).to respond_to(:virtual_media) }
      it { expect(adapter).to respond_to(:insert_virtual_media) }
      it { expect(adapter).to respond_to(:eject_virtual_media) }
      it { expect(adapter).to respond_to(:virtual_media_status) }
      it { expect(adapter).to respond_to(:mount_iso_and_boot) }
      it { expect(adapter).to respond_to(:unmount_all_media) }
    end

    # Boot configuration (Core::Boot)
    describe "boot configuration" do
      it { expect(adapter).to respond_to(:boot_config) }
      it { expect(adapter).to respond_to(:boot_options) }
      it { expect(adapter).to respond_to(:set_boot_override) }
      it { expect(adapter).to respond_to(:clear_boot_override) }
      it { expect(adapter).to respond_to(:set_boot_order) }
      it { expect(adapter).to respond_to(:get_boot_devices) }
      it { expect(adapter).to respond_to(:boot_to_pxe) }
      it { expect(adapter).to respond_to(:boot_to_disk) }
      it { expect(adapter).to respond_to(:boot_to_cd) }
      it { expect(adapter).to respond_to(:boot_to_usb) }
      it { expect(adapter).to respond_to(:boot_to_bios_setup) }
    end

    # Jobs/Tasks (Core::Jobs)
    describe "jobs and tasks" do
      it { expect(adapter).to respond_to(:jobs) }
      it { expect(adapter).to respond_to(:job_status) }
      it { expect(adapter).to respond_to(:wait_for_job) }
      it { expect(adapter).to respond_to(:cancel_job) }
      it { expect(adapter).to respond_to(:jobs_summary) }
    end

    # Network (Core::Network)
    describe "network configuration" do
      it { expect(adapter).to respond_to(:get_bmc_network) }
      it { expect(adapter).to respond_to(:set_bmc_network) }
    end

    # Utility (Core::Utility)
    describe "utility functions" do
      it { expect(adapter).to respond_to(:sel_log) }
      it { expect(adapter).to respond_to(:accounts) }
      it { expect(adapter).to respond_to(:sessions) }
      it { expect(adapter).to respond_to(:service_info) }
      it { expect(adapter).to respond_to(:get_firmware_version) }
    end

    # Extended methods commonly expected by applications
    describe "extended methods" do
      it { expect(adapter).to respond_to(:system_health) }
      it { expect(adapter).to respond_to(:bmc_info) }
    end

    # Optional but recommended
    describe "optional methods" do
      it "may respond to pci_devices" do
        if adapter.respond_to?(:pci_devices)
          expect(adapter.method(:pci_devices).arity).to eq(0)
        end
      end
    end
  end

end
