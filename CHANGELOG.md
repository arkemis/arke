# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Add changelog

## [0.4.5] - 2026-02-23

### Fixed
- Seed project merge group

## [0.4.4] - 2026-01-20

### Fixed
- Ignore other columns during import

## [0.4.3] - 2025-08-07

### Fixed
- Load metadata

## [0.4.2] - 2025-07-22

### Changed
- Return struct format for link_ref parameter

## [0.4.1] - 2025-06-06

### Fixed
- If file header different than requirement header return error

## [0.4.0] - 2025-06-03

### Added
- Add nested filters and order

## [0.3.17] - 2025-04-10

### Fixed
- Gh action
- Parse_value now correctly handles string parameters with multiple: true

## [0.3.16] - 2025-02-14

### Changed
- Changed current_resource to get_member
- Create custom error ArkeError and case of usage

### Fixed
- Export data encode

## [0.3.14] - 2024-12-18

### Added
- Add type to link_manager

## [0.3.13] - 2024-11-26

### Fixed
- Offset and limit defaults

## [0.3.12] - 2024-10-25

### Fixed
- On_unit_import and before_unit_import

## [0.3.11] - 2024-10-24

### Changed
- Export data endpoint

## [0.3.10] - 2024-09-03

### Changed
- File storage generic

## [0.3.9] - 2024-08-12

### Added
- Add type of parameter in export data tasks

## [0.3.8] - 2024-08-02

### Added
- Add overridable func for import

## [0.3.7] - 2024-07-23

### Fixed
- Form data undefined to nil
- Form data null to nil

## [0.3.6] - 2024-06-26

### Changed
- Align dev

## [0.3.5] - 2024-06-21

### Changed
- Lowercase parameter and its validation

## [0.3.4] - 2024-06-07

### Changed
- Parameter value arke

### Fixed
- Order export data

## [0.3.3] - 2024-05-29

### Fixed
- Export_data

## [0.3.2] - 2024-05-21

### Changed
- Ignore logs in test env
- Export data task
- Starting_unit in link info

## [0.3.1] - 2024-05-14

### Changed
- Handle public files

## [0.3.0] - 2024-04-23

### Changed
- Set version to v0.3.0
- Registry-file

## [0.1.33] - 2024-03-28

### Changed
- Improved import function in system

## [0.1.32] - 2024-03-15

### Changed
- Import function for arke

## [0.1.31] - 2024-02-01

### Changed
- Set version to v0.1.31

### Fixed
- Check metadata validity in unit update function

## [0.1.30] - 2024-01-31

### Fixed
- Used utc now

## [0.1.29] - 2024-01-31

### Fixed
- Handle updated_at in query manager update function

## [0.1.28] - 2024-01-30

### Added
- Add versioning by mix version command

### Fixed
- Parameter association
- Updated_at column value

## [0.1.27] - 2024-01-17

### Changed
- Set version to v0.1.27

### Fixed
- Get groups by arke

## [0.1.26] - 2023-12-22

### Changed
- General fixes

## [0.1.25] - 2023-12-12

### Changed
- Adedd old_unit as parameter in on_update function handler

## [0.1.24] - 2023-12-04

### Changed
- Set version to v0.1.24

### Fixed
- Update node + metadata is not a pk in arke_link

## [0.1.23] - 2023-11-15

### Fixed
- Fix form data update

## [0.1.22] - 2023-11-08

### Fixed
- Handle parameters links on update

## [0.1.21] - 2023-10-27

### Removed
- Remove load_links at false for links

## [0.1.20] - 2023-10-26

### Fixed
- Exclude arke_link from handle link units

## [0.1.19] - 2023-10-26

### Changed
- Handle arke file upload and load_files opts in struct encode

## [0.1.18] - 2023-10-17

### Changed
- Handled unit and arke functions and improved unit_manager macro

## [0.1.17] - 2023-10-11

### Fixed
- Used in gcp utils env and not config

## [0.1.15] - 2023-10-05

### Fixed
- Fixed hanlde link_parameters

## [0.1.14] - 2023-10-05

### Changed
- Handle arke file parameter

## [0.1.12] - 2023-08-30

### Added
- Add parameter to reset_password_token arke

### Changed
- Set version to v0.1.12

### Fixed
- Datetime from unix

## [0.1.11] - 2023-08-01

### Changed
- Set version to v0.1.11
- Handle link parameter direction

### Fixed
- Handle_link_parameter get_by fix
- Handle_link_parameters to pass id

## [0.1.10] - 2023-07-20

### Added
- Add no_whitespace parameter
- Add isnull operator to list
- Add dependabot.yml to open PR for deps updates
- Add boolean type validation

### Changed
- Set version to v0.1.10
- Set version to v0.1.9
- Handled load_values in struct encode

### Fixed
- Rename link_ref
- Parse inserted_at and updated_at using DatetimeHandler
- Throw error when id is passed as number to Units
- Enable multiple integer/float parameters

## [0.1.8] - 2023-06-29

### Changed
- Set version to v0.1.8

### Fixed
- Link_manager add node handling if parameters are not Unit
- Init

## [0.1.7] - 2023-06-15

### Changed
- Set version to v0.1.7

### Fixed
- Params manager get alias

## [0.1.6] - 2023-06-14

### Changed
- Handle parameter_manager improvements

## [0.1.5] - 2023-05-31

### Added
- Add on_struct_encode overridable function for intercepting unit gets

### Changed
- Set version to v0.1.5

### Fixed
- Typo
- BaseFilter is now parsing datetime filters
- Prevent error in validate_values when values is nil
- Handled ref for arke_or_group_id parameter

### Removed
- Remove configuration in favor of metadata

## [0.1.4] - 2023-05-19

### Changed
- Set version to v0.1.4
- Change action

### Fixed
- Struct manager use datetime handler

## [0.1.3] - 2023-05-18

### Added
- Add publish to hex workflow

[unreleased]: https://github.com///compare/v0.4.5...HEAD
[0.4.5]: https://github.com///compare/v0.4.4...v0.4.5
[0.4.4]: https://github.com///compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com///compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com///compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com///compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com///compare/v0.3.17...v0.4.0
[0.3.17]: https://github.com///compare/v0.3.16...v0.3.17
[0.3.16]: https://github.com///compare/v0.3.14...v0.3.16
[0.3.14]: https://github.com///compare/v0.3.13...v0.3.14
[0.3.13]: https://github.com///compare/v0.3.12...v0.3.13
[0.3.12]: https://github.com///compare/v0.3.11...v0.3.12
[0.3.11]: https://github.com///compare/v0.3.10...v0.3.11
[0.3.10]: https://github.com///compare/v0.3.9...v0.3.10
[0.3.9]: https://github.com///compare/v0.3.8...v0.3.9
[0.3.8]: https://github.com///compare/v0.3.7...v0.3.8
[0.3.7]: https://github.com///compare/v0.3.6...v0.3.7
[0.3.6]: https://github.com///compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com///compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com///compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com///compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com///compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com///compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com///compare/v0.1.33...v0.3.0
[0.1.33]: https://github.com///compare/v0.1.32...v0.1.33
[0.1.32]: https://github.com///compare/v0.1.31...v0.1.32
[0.1.31]: https://github.com///compare/v0.1.30...v0.1.31
[0.1.30]: https://github.com///compare/v0.1.29...v0.1.30
[0.1.29]: https://github.com///compare/v0.1.28...v0.1.29
[0.1.28]: https://github.com///compare/v0.1.27...v0.1.28
[0.1.27]: https://github.com///compare/v0.1.26...v0.1.27
[0.1.26]: https://github.com///compare/v0.1.25...v0.1.26
[0.1.25]: https://github.com///compare/v0.1.24...v0.1.25
[0.1.24]: https://github.com///compare/v0.1.23...v0.1.24
[0.1.23]: https://github.com///compare/v0.1.22...v0.1.23
[0.1.22]: https://github.com///compare/v0.1.21...v0.1.22
[0.1.21]: https://github.com///compare/v0.1.20...v0.1.21
[0.1.20]: https://github.com///compare/v0.1.19...v0.1.20
[0.1.19]: https://github.com///compare/v0.1.18...v0.1.19
[0.1.18]: https://github.com///compare/v0.1.17...v0.1.18
[0.1.17]: https://github.com///compare/v0.1.16...v0.1.17
[0.1.15]: https://github.com///compare/v0.1.14...v0.1.15
[0.1.14]: https://github.com///compare/v0.1.13...v0.1.14
[0.1.12]: https://github.com///compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com///compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com///compare/v0.1.8...v0.1.10
[0.1.8]: https://github.com///compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com///compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com///compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com///compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com///compare/v0.1.3...v0.1.4

<!-- generated by git-cliff -->
