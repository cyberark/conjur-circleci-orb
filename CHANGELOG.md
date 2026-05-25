# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-28

### Security

- **[BREAKING]** Jobs that connect to SM over plain `http://` without `allow_insecure_http: true` fail during URL validation before authentication.
- Secrets Manager `curl` calls use `--proto https`, `--proto-redir https`, and `--ssl-reqd` unless the appliance URL is `http://` and `allow_insecure_http` is enabled.

### Added

- `allow_insecure_http` orb parameter on `retrieve_secret` (default `false`). Must be set to `true` when the appliance URL uses `http://`.

### Changed

- Plain `http://` appliance URLs are rejected when `allow_insecure_http` is `false`.
- When `allow_insecure_http` is `true`, a warning is emitted that OIDC tokens and secrets may be sent in cleartext.

## [0.0.3] - 2025-11-20

### Added

- Define default telemetry header values to ensure successful telemetry data processing.

## [0.0.2] - 2025-11-05

### Added

- Unit Test Coverage and CircleCI Orb Example Updates

## [0.0.1] - 2023-05-19

### Added

- Example Atlantis/Infrapool Pipeline
