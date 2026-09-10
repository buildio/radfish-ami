# Changelog

## [0.2.0] - 2026-09-11
### Changed
- **Breaking:** `set_boot_override` and the `boot_to_*` helpers take
  `persistence:` (a Redfish string such as `"Once"` or `"Continuous"`)
  instead of the boolean `persistent:`. (#1, thanks @davispuh)
- Requires radfish >= 0.3.0.
- Note: `mode:` is accepted for interface parity but not yet sent -- the
  payload carries no `BootSourceOverrideMode`.

### Added
- CI on push and pull request, and a release workflow publishing to RubyGems
  through trusted publishing (OIDC).
