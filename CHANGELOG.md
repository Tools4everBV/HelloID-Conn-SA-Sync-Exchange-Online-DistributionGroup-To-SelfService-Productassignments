# Changelog

## 1.0.2

### Fixed
- Do not pass a null `Filter` parameter to `Get-DistributionGroup` when `$exchangeGroupsFilter` is empty, so the sync keeps working when no group filter is configured.
