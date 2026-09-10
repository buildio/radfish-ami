# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Use a sibling radfish checkout when there is one (the usual local setup), and
# fall back to the released gem otherwise, so CI does not need two checkouts.
radfish_path = File.expand_path("../radfish", __dir__)
gem "radfish", path: radfish_path if Dir.exist?(radfish_path)

group :development, :test do
  gem "debug", "~> 1.0"
end
