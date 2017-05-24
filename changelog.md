# Changelog

## 0.3.1+1
- fix an NPE when analyzing a directory without a pubspec.yaml file

## 0.3.0
- re-write the `check` command to be based on the analysis server

## 0.2.6
- rev to `0.30.0-alpha.1` of the analyzer
- print error codes in the output (useful for `// ignore: foo_bar` comments)

## 0.2.5
- rev to `0.28.1` of the analyzer

## 0.2.4
- rev to the latest version of the analysis engine (`0.27.4`)

## 0.2.3
- rev to the latest version of the analysis engine (`0.27.4-alpha.13`)

## 0.2.2
- rev to the latest version of the analysis engine to capture some fixes to
  strong mode warnings

## 0.2.1
- rev to the latest version of the analysis engine
- support conditional directives and super mixins

## 0.2.0
- bump version to 0.2.0

## 0.1.4
- add support for .analysis_options file excludes
- add support for strong mode analysis

## 0.1.3+1
- fixed an issue with the `check` command on windows

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
