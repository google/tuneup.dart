# tuneup.dart

A command-line tool to manipulate and inspect your Dart projects.

[![Build Status](https://travis-ci.org/google/tuneup.dart.svg)](https://travis-ci.org/google/tuneup.dart)
[![Coverage Status](https://img.shields.io/coveralls/google/tuneup.dart.svg)](https://coveralls.io/r/google/tuneup.dart)

## Installing

To install, run:

    pub global activate tuneup

## Running

Run `tuneup --help` (or `pub global run tuneup --help`) to see a list of available commands.

- *init*: create a new project
- *check*: analyze all the source code in the project - fail if there are any
   errors (This is the default action)
- *stats*: display metadata and statistics about the project
- *trim*: trim unwanted whitespace from your source
- *clean*: clean the project (remove the build/ directory)

Then run a tuneup command, like `check`:

    pub global run tuneup check

or,

    tuneup check

from the root of your project.

## Filing Issues

Please file reports on the [GitHub Issue Tracker](https://github.com/google/tuneup.dart/issues).

## Disclaimer

This is not an official Google product.
