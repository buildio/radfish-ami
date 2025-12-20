# frozen_string_literal: true

require_relative "lib/radfish/ami/version"

Gem::Specification.new do |spec|
  spec.name = "radfish-ami"
  spec.version = Radfish::Ami::VERSION
  spec.authors = ["Jonathan Siegel"]
  spec.email = ["248302+usiegj00@users.noreply.github.com"]

  spec.summary = "AMI/ASRockRack adapter for Radfish"
  spec.description = "AMI BMC adapter for Radfish Redfish API client. Provides support for ASRockRack servers and other systems using AMI MegaRAC BMC firmware."
  spec.homepage = "https://github.com/buildio/radfish-ami"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib}/**/*", "LICENSE", "README.md", "*.gemspec"].reject { |f| File.directory?(f) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "radfish", "~> 0.2"
  spec.add_dependency "ostruct", ">= 0"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end
