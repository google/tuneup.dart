# Changelog

## 0.1.3
- upgraded the analyzer version to capture a change to analyzing unnamed
  libraries
- added a `--directory` flag to support analyzing something besides the current
  working directory

## 0.1.2
- fixed an issue analyzing libraries that were referred to by both self-references
  (package: references) and relative path references

## 0.1.1
- added support for `.packages` files
- added support for SDK extensions

## 0.1.0
- upgraded to `analyzer` 0.26.0 and `test` 0.12.0

## 0.0.5
- made `check` the default command

## 0.0.4
- upgraded to the latest analyzer; now supports async / await syntax

## 0.0.3+1
- bug fixes to the `init` command

## 0.0.3
- added support for yaml files to `trim`

## 0.0.2
- added a `trim` command
- renamed `analyze` to `check`

## 0.0.1
- initial version, created by Stagehand
