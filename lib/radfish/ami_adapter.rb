# frozen_string_literal: true

require 'ostruct'

module Radfish
  class AmiAdapter < Core::BaseClient
    include Core::Power
    include Core::System
    include Core::Storage
    include Core::VirtualMedia
    include Core::Boot
    include Core::Jobs
    include Core::Utility
    include Core::Network

    # AMI BMC uses "Self" as the default system/manager/chassis ID
    SYSTEM_ID = "Self"
    MANAGER_ID = "Self"
    CHASSIS_ID = "Self"

    def vendor
      "ami"
    end

    # Allow adapter to be used directly where code expects client.adapter
    def adapter
      self
    end

    # Session management
    def login
      @session = Core::Session.new(self)
      @session.create
    end

    def logout
      return true unless @session
      result = @session.delete
      @session = nil
      result
    end

    def authenticated_request(method, path, **options)
      ensure_session!

      headers = options[:headers] || {}
      headers["X-Auth-Token"] = @session.x_auth_token
      headers["Accept"] ||= "application/json"
      headers["Content-Type"] ||= "application/json" if [:post, :put, :patch].include?(method)
      headers["Host"] = host_header if host_header

      options[:headers] = headers

      case method
      when :get
        http_get(path, **options)
      when :post
        http_post(path, **options)
      when :put
        http_put(path, **options)
      when :patch
        http_patch(path, **options)
      when :delete
        http_delete(path, **options)
      else
        raise ArgumentError, "Unknown HTTP method: #{method}"
      end
    end

    # Power management
    def power_status
      response = authenticated_request(:get, "/redfish/v1/Systems/#{SYSTEM_ID}")
      if response.status == 200
        data = JSON.parse(response.body)
        data["PowerState"]
      else
        raise Error, "Failed to get power status: #{response.status}"
      end
    end

    def power_on
      perform_reset_action("On")
    end

    def power_off(force: true)
      if force
        perform_reset_action("ForceOff")
      else
        perform_reset_action("GracefulShutdown")
      end
    end

    def power_restart(force: true)
      if force
        perform_reset_action("ForceRestart")
      else
        # Graceful restart: shutdown then power on
        power_off(force: false)
        sleep 5
        power_on
      end
    end

    def power_cycle
      perform_reset_action("PowerCycle")
    end

    def reset_type_allowed
      response = authenticated_request(:get, "/redfish/v1/Systems/#{SYSTEM_ID}/ResetActionInfo")
      if response.status == 200
        data = JSON.parse(response.body)
        params = data.dig("Parameters") || []
        reset_param = params.find { |p| p["Name"] == "ResetType" }
        reset_param&.dig("AllowableValues") || []
      else
        # Fallback to common AMI reset types
        %w[On ForceOff ForceRestart GracefulShutdown PowerCycle]
      end
    end

    # System information
    def system_info
      response = authenticated_request(:get, "/redfish/v1/Systems/#{SYSTEM_ID}")
      raise Error, "Failed to get system info: #{response.status}" unless response.status == 200
      JSON.parse(response.body)
    end

    def service_tag
      system_info["SerialNumber"]
    end

    def make
      info = system_info
      info["Manufacturer"] || "ASRockRack"
    end

    def model
      system_info["Model"]
    end

    def serial
      system_info["SerialNumber"]
    end

    def system_health
      info = system_info
      status = info["Status"] || {}
      OpenStruct.new(
        health: status["Health"] || "Unknown",
        rollup: status["HealthRollup"] || status["Health"] || "Unknown"
      )
    end

    def bmc_info
      manager = get_manager_info
      network = get_bmc_network

      {
        firmware_version: manager["FirmwareVersion"],
        redfish_version: service_root["RedfishVersion"],
        mac_address: network["mac_address"],
        ip_address: network["ipv4_address"],
        hostname: network["hostname"],
        health: manager.dig("Status", "Health") || "OK"
      }
    end

    def cpus
      response = authenticated_request(:get, "/redfish/v1/Systems/#{SYSTEM_ID}/Processors")
      return [] unless response.status == 200

      collection = JSON.parse(response.body)
      members = collection["Members"] || []

      members.map do |member|
        cpu_response = authenticated_request(:get, member["@odata.id"])
        next nil unless cpu_response.status == 200
        data = JSON.parse(cpu_response.body)
        OpenStruct.new(
          socket: data["Socket"] || data["Id"],
          manufacturer: data["Manufacturer"],
          model: data.dig("ProcessorId", "EffectiveFamily")&.strip || data["Model"],
          cores: data["TotalCores"],
          threads: data["TotalThreads"],
          speed_mhz: data["MaxSpeedMHz"],
          health: data.dig("Status", "Health") || "Unknown"
        )
      end.compact
    end

    def memory
      response = authenticated_request(:get, "/redfish/v1/Systems/#{SYSTEM_ID}/Memory")
      return [] unless response.status == 200

      collection = JSON.parse(response.body)
      members = collection["Members"] || []

      members.map do |member|
        mem_response = authenticated_request(:get, member["@odata.id"])
        next nil unless mem_response.status == 200
        data = JSON.parse(mem_response.body)
        OpenStruct.new(
          name: data["Name"] || data["Id"],
          capacity_bytes: data["CapacityMiB"] ? data["CapacityMiB"] * 1024 * 1024 : nil,
          speed_mhz: data["OperatingSpeedMhz"],
          manufacturer: data["Manufacturer"],
          part_number: data["PartNumber"],
          serial_number: data["SerialNumber"],
          memory_type: data["MemoryDeviceType"],
          status: data.dig("Status", "Health") || "OK"
        )
      end.compact
    end

    def nics
      response = authenticated_request(:get, "/redfish/v1/Systems/#{SYSTEM_ID}/EthernetInterfaces")
      return [] unless response.status == 200

      collection = JSON.parse(response.body)
      members = collection["Members"] || []

      members.map do |member|
        nic_response = authenticated_request(:get, member["@odata.id"])
        next nil unless nic_response.status == 200
        data = JSON.parse(nic_response.body)
        OpenStruct.new(
          name: data["Name"] || data["Id"],
          mac: data["MACAddress"],
          speed_mbps: data["SpeedMbps"],
          link_status: data["LinkStatus"],
          ipv4_addresses: data["IPv4Addresses"],
          ipv6_addresses: data["IPv6Addresses"],
          status: data.dig("Status", "Health") || "OK"
        )
      end.compact
    end

    def fans
      thermal = get_thermal_data
      (thermal["Fans"] || []).map do |fan|
        OpenStruct.new(
          name: fan["Name"] || fan["MemberId"],
          rpm: fan["Reading"],
          status: fan.dig("Status", "Health") || "OK",
          min_rpm: fan["MinReadingRange"],
          max_rpm: fan["MaxReadingRange"]
        )
      end
    end

    def temperatures
      thermal = get_thermal_data
      (thermal["Temperatures"] || []).map do |temp|
        OpenStruct.new(
          name: temp["Name"] || temp["MemberId"],
          reading_celsius: temp["ReadingCelsius"],
          status: temp.dig("Status", "Health") || "OK",
          upper_threshold_critical: temp["UpperThresholdCritical"],
          upper_threshold_fatal: temp["UpperThresholdFatal"]
        )
      end
    end

    def psus
      power_data = get_power_data
      (power_data["PowerSupplies"] || []).map do |psu|
        OpenStruct.new(
          name: psu["Name"] || psu["MemberId"],
          model: psu["Model"],
          serial: psu["SerialNumber"],
          watts: psu["PowerCapacityWatts"],
          voltage: psu.dig("InputRanges", 0, "NominalVoltageVolts"),
          voltage_human: psu.dig("InputRanges", 0, "InputType"),
          status: psu.dig("Status", "Health") || "OK"
        )
      end
    end

    def power_consumption
      power_data = get_power_data
      power_data["PowerControl"]&.first || {}
    end

    def power_consumption_watts
      consumption = power_consumption
      consumption.dig("PowerMetrics", "AverageConsumedWatts") ||
        consumption.dig("PowerMetrics", "CurConsumedWatts") ||
        0
    end

    # PCI Devices
    def pci_devices
      # Try PCIeDevices endpoint first (Redfish standard)
      response = authenticated_request(:get, "/redfish/v1/Systems/#{SYSTEM_ID}/PCIeDevices")
      if response.status == 200
        collection = JSON.parse(response.body)
        members = collection["Members"] || []

        return members.map do |member|
          device_response = authenticated_request(:get, member["@odata.id"])
          next nil unless device_response.status == 200
          data = JSON.parse(device_response.body)
          OpenStruct.new(
            id: data["Id"],
            name: data["Name"],
            manufacturer: data["Manufacturer"],
            model: data["Model"],
            device_type: data["DeviceType"],
            pcie_interface: data["PCIeInterface"],
            status: data.dig("Status", "Health") || "OK"
          )
        end.compact
      end

      # Fallback: return empty array if not supported
      []
    end

    # Storage
    def storage_controllers
      response = authenticated_request(:get, "/redfish/v1/Systems/#{SYSTEM_ID}/Storage")
      return [] unless response.status == 200

      collection = JSON.parse(response.body)
      members = collection["Members"] || []

      members.map do |member|
        controller_response = authenticated_request(:get, member["@odata.id"])
        next nil unless controller_response.status == 200
        data = JSON.parse(controller_response.body)
        # Return OpenStruct - Radfish::Client will wrap in Controller
        OpenStruct.new(
          id: data["Id"],
          name: data["Name"],
          model: data["Model"],
          status: data.dig("Status", "Health"),
          "@odata.id": member["@odata.id"]
        )
      end.compact
    end

    def drives(controller)
      controller_id = if controller.is_a?(Radfish::Controller)
                        controller.id
                      elsif controller.respond_to?(:id)
                        controller.id
                      else
                        controller
                      end
      response = authenticated_request(:get, "/redfish/v1/Systems/#{SYSTEM_ID}/Storage/#{controller_id}")
      return [] unless response.status == 200

      data = JSON.parse(response.body)
      drive_refs = data["Drives"] || []

      drive_refs.map do |ref|
        drive_response = authenticated_request(:get, ref["@odata.id"])
        next nil unless drive_response.status == 200
        drive_data = JSON.parse(drive_response.body)
        OpenStruct.new(
          name: drive_data["Name"] || drive_data["Id"],
          model: drive_data["Model"],
          manufacturer: drive_data["Manufacturer"],
          serial: drive_data["SerialNumber"],
          capacity_bytes: drive_data["CapacityBytes"],
          capacity_gb: drive_data["CapacityBytes"] ? (drive_data["CapacityBytes"] / 1_000_000_000.0).round(2) : nil,
          media_type: drive_data["MediaType"],
          protocol: drive_data["Protocol"],
          status: drive_data.dig("Status", "Health") || "OK",
          certified: drive_data.dig("Oem", "Dell", "Certified") || drive_data.dig("Oem", "AMI", "Certified")
        )
      end.compact
    end

    def volumes(controller)
      controller_id = if controller.is_a?(Radfish::Controller)
                        controller.id
                      elsif controller.respond_to?(:id)
                        controller.id
                      else
                        controller
                      end
      response = authenticated_request(:get, "/redfish/v1/Systems/#{SYSTEM_ID}/Storage/#{controller_id}/Volumes")
      return [] unless response.status == 200

      collection = JSON.parse(response.body)
      members = collection["Members"] || []

      members.map do |member|
        volume_response = authenticated_request(:get, member["@odata.id"])
        next nil unless volume_response.status == 200
        data = JSON.parse(volume_response.body)
        # Return hash with normalized keys - Radfish::Client will wrap in Volume
        # Keep the raw data for adapter_data access
        data["id"] = data["Id"]
        data["name"] = data["Name"]
        data["capacity_bytes"] = data["CapacityBytes"]
        data["raid_type"] = data["RAIDType"]
        data["health"] = data.dig("Status", "Health")
        data
      end.compact
    end

    def volume_drives(volume)
      volume_id = volume.is_a?(Radfish::Volume) ? volume.id : volume
      # Get volume details to find linked drives - adapter_data is the raw hash
      volume_data = volume.is_a?(Radfish::Volume) ? volume.adapter_data : nil

      # volume_data should be a hash with "Links" -> "Drives"
      unless volume_data.is_a?(Hash)
        # Need to fetch volume data
        storage_controllers.each do |controller|
          vols = volumes(controller)
          # volumes() returns hashes now
          vol = vols.find { |v| (v["id"] || v["Id"]) == volume_id }
          if vol
            volume_data = vol
            break
          end
        end
      end

      return [] unless volume_data.is_a?(Hash)

      drive_refs = volume_data.dig("Links", "Drives") || []
      drive_refs.map do |ref|
        drive_response = authenticated_request(:get, ref["@odata.id"])
        next nil unless drive_response.status == 200
        drive_data = JSON.parse(drive_response.body)
        OpenStruct.new(
          name: drive_data["Name"] || drive_data["Id"],
          model: drive_data["Model"],
          manufacturer: drive_data["Manufacturer"],
          serial: drive_data["SerialNumber"],
          capacity_bytes: drive_data["CapacityBytes"],
          capacity_gb: drive_data["CapacityBytes"] ? (drive_data["CapacityBytes"] / 1_000_000_000.0).round(2) : nil,
          media_type: drive_data["MediaType"],
          protocol: drive_data["Protocol"],
          status: drive_data.dig("Status", "Health") || "OK"
        )
      end.compact
    end

    def storage_summary
      controllers = storage_controllers
      {
        controller_count: controllers.size,
        controllers: controllers.map do |c|
          {
            id: c.id,
            name: c.name,
            drive_count: drives(c).size,
            volume_count: volumes(c).size
          }
        end
      }
    end

    # Virtual Media
    def virtual_media
      response = authenticated_request(:get, "/redfish/v1/Managers/#{MANAGER_ID}/VirtualMedia")
      return [] unless response.status == 200

      collection = JSON.parse(response.body)
      members = collection["Members"] || []

      members.map do |member|
        vm_response = authenticated_request(:get, member["@odata.id"])
        next nil unless vm_response.status == 200
        JSON.parse(vm_response.body)
      end.compact
    end

    def virtual_media_status
      virtual_media.map do |vm|
        {
          id: vm["Id"],
          name: vm["Name"],
          media_types: vm["MediaTypes"],
          inserted: vm["Inserted"],
          image: vm["Image"],
          connected: vm["ConnectedVia"]
        }
      end
    end

    def insert_virtual_media(iso_url, device: nil)
      devices = virtual_media
      target_device = if device
                        devices.find { |d| d["Id"] == device || d["Name"]&.include?(device.to_s) }
                      else
                        # Find first CD/DVD device
                        devices.find { |d| d["MediaTypes"]&.include?("CD") || d["MediaTypes"]&.include?("DVD") }
                      end

      raise VirtualMediaNotFoundError, "No suitable virtual media device found" unless target_device

      device_path = target_device["@odata.id"]
      actions = target_device.dig("Actions", "#VirtualMedia.InsertMedia")

      if actions && actions["target"]
        # Use the InsertMedia action
        payload = { "Image" => iso_url, "Inserted" => true, "WriteProtected" => true }
        response = authenticated_request(:post, actions["target"], body: payload.to_json)
      else
        # Fallback to PATCH method
        payload = { "Image" => iso_url, "Inserted" => true, "WriteProtected" => true }
        response = authenticated_request(:patch, device_path, body: payload.to_json)
      end

      if response.status.between?(200, 204)
        debug "Virtual media inserted successfully", 1, :green
        true
      else
        error_msg = begin
                      JSON.parse(response.body).dig("error", "message")
                    rescue
                      response.body
                    end
        raise VirtualMediaError, "Failed to insert virtual media: #{error_msg}"
      end
    end

    def eject_virtual_media(device: nil)
      devices = virtual_media
      target_device = if device
                        devices.find { |d| d["Id"] == device || d["Name"]&.include?(device.to_s) }
                      else
                        # Find first mounted device
                        devices.find { |d| d["Inserted"] == true }
                      end

      return true unless target_device && target_device["Inserted"]

      device_path = target_device["@odata.id"]
      actions = target_device.dig("Actions", "#VirtualMedia.EjectMedia")

      if actions && actions["target"]
        response = authenticated_request(:post, actions["target"], body: "{}".to_json)
      else
        payload = { "Image" => nil, "Inserted" => false }
        response = authenticated_request(:patch, device_path, body: payload.to_json)
      end

      response.status.between?(200, 204)
    end

    def unmount_all_media
      virtual_media.each do |device|
        next unless device["Inserted"]
        eject_virtual_media(device: device["Id"])
      end
      true
    end

    def mount_iso_and_boot(iso_url, device: nil)
      insert_virtual_media(iso_url, device: device)
      set_boot_override("Cd", persistent: false)
      power_restart(force: true)
    end

    # Boot configuration
    def boot_config
      info = system_info
      info["Boot"] || {}
    end

    def boot_options
      boot = boot_config
      {
        "boot_source_override_enabled" => boot["BootSourceOverrideEnabled"],
        "boot_source_override_target" => boot["BootSourceOverrideTarget"],
        "boot_source_override_mode" => boot["BootSourceOverrideMode"],
        "boot_order" => boot["BootOrder"],
        "allowed_targets" => boot["BootSourceOverrideTarget@Redfish.AllowableValues"]
      }
    end

    def set_boot_override(target, persistent: false)
      enabled = persistent ? "Continuous" : "Once"
      payload = {
        "Boot" => {
          "BootSourceOverrideTarget" => target,
          "BootSourceOverrideEnabled" => enabled
        }
      }

      response = authenticated_request(:patch, "/redfish/v1/Systems/#{SYSTEM_ID}", body: payload.to_json)

      if response.status.between?(200, 204)
        debug "Boot override set to #{target} (#{enabled})", 1, :green
        true
      else
        error_msg = begin
                      JSON.parse(response.body).dig("error", "message")
                    rescue
                      response.body
                    end
        raise Error, "Failed to set boot override: #{error_msg}"
      end
    end

    def clear_boot_override
      payload = {
        "Boot" => {
          "BootSourceOverrideTarget" => "None",
          "BootSourceOverrideEnabled" => "Disabled"
        }
      }

      response = authenticated_request(:patch, "/redfish/v1/Systems/#{SYSTEM_ID}", body: payload.to_json)
      response.status.between?(200, 204)
    end

    def set_boot_order(devices)
      payload = {
        "Boot" => {
          "BootOrder" => devices
        }
      }

      response = authenticated_request(:patch, "/redfish/v1/Systems/#{SYSTEM_ID}", body: payload.to_json)
      response.status.between?(200, 204)
    end

    def get_boot_devices
      boot_config["BootOrder"] || []
    end

    def boot_to_pxe(persistent: false)
      set_boot_override("Pxe", persistent: persistent)
    end

    def boot_to_disk(persistent: false)
      set_boot_override("Hdd", persistent: persistent)
    end

    def boot_to_cd(persistent: false)
      set_boot_override("Cd", persistent: persistent)
    end

    def boot_to_usb(persistent: false)
      set_boot_override("Usb", persistent: persistent)
    end

    def boot_to_bios_setup(persistent: false)
      set_boot_override("BiosSetup", persistent: persistent)
    end

    # Jobs/Tasks
    def jobs
      response = authenticated_request(:get, "/redfish/v1/TaskService/Tasks")
      return [] unless response.status == 200

      collection = JSON.parse(response.body)
      members = collection["Members"] || []

      members.map do |member|
        task_response = authenticated_request(:get, member["@odata.id"])
        next nil unless task_response.status == 200
        JSON.parse(task_response.body)
      end.compact
    end

    def job_status(job_id)
      response = authenticated_request(:get, "/redfish/v1/TaskService/Tasks/#{job_id}")
      if response.status == 200
        JSON.parse(response.body)
      else
        raise TaskError, "Failed to get task status: #{response.status}"
      end
    end

    def wait_for_job(job_id, timeout: 600)
      start_time = Time.now
      loop do
        status = job_status(job_id)
        state = status["TaskState"]

        case state
        when "Completed"
          return status
        when "Exception", "Killed", "Cancelled"
          raise TaskFailedError, "Task #{job_id} failed: #{status['Messages']}"
        end

        if Time.now - start_time > timeout
          raise TaskTimeoutError, "Task #{job_id} timed out after #{timeout} seconds"
        end

        sleep 5
      end
    end

    def cancel_job(job_id)
      response = authenticated_request(:delete, "/redfish/v1/TaskService/Tasks/#{job_id}")
      response.status.between?(200, 204)
    end

    def clear_completed_jobs
      jobs.each do |job|
        next unless %w[Completed Exception Killed Cancelled].include?(job["TaskState"])
        cancel_job(job["Id"])
      end
      true
    end

    def jobs_summary
      all_jobs = jobs
      {
        total: all_jobs.size,
        running: all_jobs.count { |j| j["TaskState"] == "Running" },
        completed: all_jobs.count { |j| j["TaskState"] == "Completed" },
        failed: all_jobs.count { |j| %w[Exception Killed Cancelled].include?(j["TaskState"]) }
      }
    end

    # Utility
    def sel_log
      response = authenticated_request(:get, "/redfish/v1/Systems/#{SYSTEM_ID}/LogServices/Log1/Entries")
      return [] unless response.status == 200

      collection = JSON.parse(response.body)
      collection["Members"] || []
    end

    def clear_sel_log
      response = authenticated_request(:post, "/redfish/v1/Systems/#{SYSTEM_ID}/LogServices/Log1/Actions/LogService.ClearLog", body: "{}".to_json)
      response.status.between?(200, 204)
    end

    def sel_summary(limit: 10)
      entries = sel_log.first(limit)
      entries.map do |entry|
        {
          id: entry["Id"],
          created: entry["Created"],
          severity: entry["Severity"],
          message: entry["Message"]
        }
      end
    end

    def accounts
      response = authenticated_request(:get, "/redfish/v1/AccountService/Accounts")
      return [] unless response.status == 200

      collection = JSON.parse(response.body)
      members = collection["Members"] || []

      members.map do |member|
        account_response = authenticated_request(:get, member["@odata.id"])
        next nil unless account_response.status == 200
        JSON.parse(account_response.body)
      end.compact
    end

    def create_account(username:, password:, role: "Administrator")
      payload = {
        "UserName" => username,
        "Password" => password,
        "RoleId" => role
      }

      response = authenticated_request(:post, "/redfish/v1/AccountService/Accounts", body: payload.to_json)

      if response.status == 201
        JSON.parse(response.body)
      else
        error_msg = begin
                      JSON.parse(response.body).dig("error", "message")
                    rescue
                      response.body
                    end
        raise Error, "Failed to create account: #{error_msg}"
      end
    end

    def delete_account(username)
      account = accounts.find { |a| a["UserName"] == username }
      raise NotFoundError, "Account not found: #{username}" unless account

      response = authenticated_request(:delete, account["@odata.id"])
      response.status.between?(200, 204)
    end

    def update_account_password(username:, new_password:)
      account = accounts.find { |a| a["UserName"] == username }
      raise NotFoundError, "Account not found: #{username}" unless account

      payload = { "Password" => new_password }
      response = authenticated_request(:patch, account["@odata.id"], body: payload.to_json)
      response.status.between?(200, 204)
    end

    def sessions
      response = authenticated_request(:get, "/redfish/v1/SessionService/Sessions")
      return [] unless response.status == 200

      collection = JSON.parse(response.body)
      members = collection["Members"] || []

      members.map do |member|
        session_response = authenticated_request(:get, member["@odata.id"])
        next nil unless session_response.status == 200
        JSON.parse(session_response.body)
      end.compact
    end

    def service_info
      service_root
    end

    def get_firmware_version
      response = authenticated_request(:get, "/redfish/v1/Managers/#{MANAGER_ID}")
      if response.status == 200
        data = JSON.parse(response.body)
        data["FirmwareVersion"]
      else
        nil
      end
    end

    # Network configuration
    def get_bmc_network
      response = authenticated_request(:get, "/redfish/v1/Managers/#{MANAGER_ID}/EthernetInterfaces")
      return {} unless response.status == 200

      collection = JSON.parse(response.body)
      members = collection["Members"] || []
      return {} if members.empty?

      # Get the first interface (typically the main BMC interface)
      interface_response = authenticated_request(:get, members.first["@odata.id"])
      return {} unless interface_response.status == 200

      data = JSON.parse(interface_response.body)

      ipv4 = data.dig("IPv4Addresses", 0) || {}
      dhcp_enabled = data.dig("DHCPv4", "DHCPEnabled")
      {
        "id" => data["Id"],
        "hostname" => data["HostName"],
        "fqdn" => data["FQDN"],
        "mac_address" => data["MACAddress"],
        "ipv4_address" => ipv4["Address"],
        "subnet_mask" => ipv4["SubnetMask"],
        "gateway" => ipv4["Gateway"],
        "mode" => dhcp_enabled ? "DHCP" : "Static",
        "address_origin" => ipv4["AddressOrigin"],
        "dhcp_enabled" => dhcp_enabled,
        "dns_servers" => data["NameServers"]
      }
    end

    def set_bmc_network(ip_address: nil, subnet_mask: nil, gateway: nil,
                        dns_primary: nil, dns_secondary: nil, hostname: nil,
                        dhcp: false)
      response = authenticated_request(:get, "/redfish/v1/Managers/#{MANAGER_ID}/EthernetInterfaces")
      return false unless response.status == 200

      collection = JSON.parse(response.body)
      members = collection["Members"] || []
      return false if members.empty?

      interface_path = members.first["@odata.id"]

      if dhcp
        payload = {
          "DHCPv4" => { "DHCPEnabled" => true }
        }
      else
        payload = {}

        if ip_address || subnet_mask || gateway
          payload["IPv4Addresses"] = [{
            "Address" => ip_address,
            "SubnetMask" => subnet_mask,
            "Gateway" => gateway
          }.compact]
        end

        if dns_primary || dns_secondary
          payload["NameServers"] = [dns_primary, dns_secondary].compact
        end

        payload["HostName"] = hostname if hostname

        payload["DHCPv4"] = { "DHCPEnabled" => false }
      end

      response = authenticated_request(:patch, interface_path, body: payload.to_json)
      response.status.between?(200, 204)
    end

    private

    def ensure_session!
      unless @session&.x_auth_token
        # Auto-login if not already logged in
        unless login
          raise AuthenticationError, "Failed to authenticate. Check credentials."
        end
      end
    end

    def perform_reset_action(reset_type)
      payload = { "ResetType" => reset_type }
      response = authenticated_request(
        :post,
        "/redfish/v1/Systems/#{SYSTEM_ID}/Actions/ComputerSystem.Reset",
        body: payload.to_json
      )

      if response.status.between?(200, 204)
        debug "Reset action #{reset_type} performed successfully", 1, :green
        true
      else
        error_msg = begin
                      JSON.parse(response.body).dig("error", "message")
                    rescue
                      response.body
                    end
        raise Error, "Failed to perform reset action #{reset_type}: #{error_msg}"
      end
    end

    def get_thermal_data
      response = authenticated_request(:get, "/redfish/v1/Chassis/#{CHASSIS_ID}/Thermal")
      if response.status == 200
        JSON.parse(response.body)
      else
        {}
      end
    end

    def get_power_data
      response = authenticated_request(:get, "/redfish/v1/Chassis/#{CHASSIS_ID}/Power")
      if response.status == 200
        JSON.parse(response.body)
      else
        {}
      end
    end

    def get_manager_info
      response = authenticated_request(:get, "/redfish/v1/Managers/#{MANAGER_ID}")
      if response.status == 200
        JSON.parse(response.body)
      else
        {}
      end
    end

    def service_root
      @service_root ||= begin
        response = authenticated_request(:get, "/redfish/v1")
        if response.status == 200
          JSON.parse(response.body)
        else
          {}
        end
      end
    end
  end

  # Register the AMI adapter
  register_adapter("ami", AmiAdapter)
  register_adapter("asrockrack", AmiAdapter)
end
