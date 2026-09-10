# Radfish-AMI

AMI BMC adapter for the [Radfish](https://github.com/buildio/radfish) Redfish API client. Provides support for ASRockRack servers and other systems using AMI MegaRAC BMC firmware.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'radfish-ami'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install radfish-ami
```

## Usage

The adapter is automatically registered when you require the gem:

```ruby
require 'radfish-ami'

# Connect to an ASRockRack server
client = Radfish.connect(
  host: 'bmc.example.com',
  username: 'admin',
  password: 'your-password',
  vendor: 'ami'  # or 'asrockrack'
)

# Get system information
puts client.system_info

# Power operations
puts client.power_status  # => "On"
client.power_restart(force: true)

# Virtual media
client.insert_virtual_media('http://example.com/boot.iso')
client.set_boot_override('Cd', persistence: 'Once')
client.power_restart

# Thermal data
client.fans.each { |fan| puts "#{fan['Name']}: #{fan['Reading']} RPM" }
client.temperatures.each { |t| puts "#{t['Name']}: #{t['ReadingCelsius']}C" }

# Storage
client.storage_controllers.each do |controller|
  puts "Controller: #{controller.name}"
  client.drives(controller).each { |d| puts "  Drive: #{d['Name']}" }
end

# Disconnect
client.logout
```

## Supported Features

- **Power Management**: Power on, off, restart, cycle, status
- **System Information**: Make, model, serial, BIOS version, CPU, memory, NICs
- **Thermal Monitoring**: Fan speeds, temperatures
- **Power Monitoring**: PSU status, power consumption
- **Storage**: Controllers, drives, volumes
- **Virtual Media**: Insert/eject ISO images
- **Boot Configuration**: Set boot order, one-time boot overrides
- **Network Configuration**: BMC network settings
- **Account Management**: Create, delete, update user accounts
- **SEL Log**: Read and clear system event logs
- **Task/Job Management**: Monitor long-running operations

## Tested Hardware

- ASRockRack GENOAD8UD-2T/X550 (AMD EPYC)
- Other ASRockRack servers with AMI MegaRAC BMC

## License

MIT License - see LICENSE file.
