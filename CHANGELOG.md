# Changelog

## [0.2.1] - 2026-09-11
### Fixed
- `set_boot_override` sends `BootSourceOverrideMode` when a `mode:` is given.
  The parameter was accepted for interface parity in 0.2.0 but never reached
  the payload, so `radfish boot cd --uefi` silently did nothing about the mode
  on this vendor. Omitted when `mode:` is nil, as before, since BMCs without
  the property reject it.

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
