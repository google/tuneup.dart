[![Dart](https://github.com/google/tuneup.dart/actions/workflows/build.yaml/badge.svg)](https://github.com/google/tuneup.dart/actions/workflows/build.yaml)
[![pub package](https://img.shields.io/pub/v/tuneup.svg)](https://pub.dev/packages/tuneup)

A command-line tool to manipulate and inspect your Dart projects.

## Update: Discontinued

Note, this package has been discontinued. Since `tuneup` was initially created
the `dart` command line tool has largely supplanted this tool's functionality
(with `dart create`, `dart analyze`, ...).

The discontinuation (and any discussion about it) can be tracked at
https://github.com/google/tuneup.dart/issues/96.

## Installing

To install, run:

    dart pub global activate tuneup

## Running

Run `tuneup --help` (or `dart pub global run tuneup --help`) to see a list of
available commands.

- *init*: create a new project
- *check*: analyze all the source code in the project - fail if there are any
   errors (this is the default action)
- *stats*: display metadata and statistics about the project
- *trim*: trim unwanted whitespace from your source
- *clean*: clean the project (remove the build/ directory)

Then run a tuneup command, like `check`:

    dart pub global run tuneup check

or,

    tuneup check

from the root of your project.

## Filing Issues

Please file reports on the
[GitHub Issue Tracker](https://github.com/google/tuneup.dart/issues).

## Disclaimer

This is not an official Google product.
