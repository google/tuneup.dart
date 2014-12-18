# tuneup.dart

A command-line tool to manipulate and inspect your Dart projects.

[![Build Status](https://travis-ci.org/google/tuneup.dart.svg)](https://travis-ci.org/google/tuneup.dart)

## Installing

To install, run:

    pub global activate tuneup

## Running

Run `tuneup` (or `pub global run tuneup`) to see a list of available commands.

- *init*: create a new project
- *stats*: display metadata and statistics about the project
- *analyze*: analyze all the source code in the project - fail if there are any
   errors
- *clean*: clean the project (remove the build/ directory)

Then run a tuneup command, like analyze:

    pub global run tuneup analyze

or,

    tuneup analyze

from the root of your project.

## Filing Issues

Please file reports on the [GitHub Issue Tracker](https://github.com/google/tuneup.dart/issues)

## Disclaimer

This is not an official Google product.
