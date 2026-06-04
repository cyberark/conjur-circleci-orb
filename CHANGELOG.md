# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [0.0.4] - 2025-05-27

### Fix

- Removed `PARAM_INTEGR` debug mode that logged fetched secret values to step output.
- Secret values written to $BASH_ENV now use printf with Bash %q so they are shell-escaped and cannot inject commands when later steps source $BASH_ENV.
- Replaced `eval` on orb parameters with `resolve_param_value`, which only resolves a whole-string `${VAR_NAME}` reference via indirect expansion and otherwise keeps the configured value literal.

## [0.0.3] - 2025-11-20

### Added

- Define default telemetry header values to ensure successful telemetry data processing.

## [0.0.2] - 2025-11-05

### Added

- Unit Test Coverage and CircleCI Orb Example Updates

## [0.0.1] - 2023-05-19

### Added

- Example Atlantis/Infrapool Pipeline
