// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/**
 * TODO: doc
 */
library tuneup;

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';

import 'src/analyze.dart';
import 'src/clean.dart';
import 'src/common.dart';
import 'src/info.dart';
import 'src/init.dart';

export 'src/common.dart' show CliLogger;

// This version must be updated in tandem with the pubspec version.
const String APP_VERSION = '0.0.1';
const String APP_NAME = "tuneup";

// TODO: --dart-sdk

// TODO: --package-root

class Tuneup {
  final CliLogger logger;
  final Map<String, Command> _commands = {};

  Tuneup([this.logger = const CliLogger()]) {
    _addCommand(new InitCommand());
    _addCommand(new InfoCommand());
    _addCommand(new AnalyzeCommand());
    _addCommand(new CleanCommand());
  }

  void _addCommand(Command command) {
    _commands[command.name] = command;
  }

  Future processArgs(List<String> args, {Directory directory}) {
    if (directory == null) directory = Directory.current;

    ArgParser argParser = _createArgParser();

    ArgResults options;

    try {
      options = argParser.parse(args);
    } catch (e, st) {
      // FormatException: Could not find an option named "foo".
      if (e is FormatException) {
        _out('Error: ${e.message}');
        return new Future.error(new ArgError(e.message));
      } else {
        return new Future.error(e, st);
      }
    }

    if (options['version']) {
      _out('${APP_NAME} version ${APP_VERSION}');
      return new Future.value();
    }

    if (options['help'] || options.command == null) {
      _usage(argParser);
      return new Future.value();
    }

    Command command = _commands[options.command.name];
    Project project = new Project(directory, logger);
    return command.execute(project, options.command);
  }

  ArgParser _createArgParser() {
    ArgParser parser = new ArgParser();

    parser.addFlag('help', abbr: 'h', negatable: false, help: 'Help!');
    parser.addFlag('version', negatable: false,
        help: 'Display the application version.');

    ArgParser commandParser = parser.addCommand('init');
    commandParser.addFlag('override', negatable: false,
        help: 'Force generation of the sample project.');

    parser.addCommand('pub');

    parser.addCommand('info');

    commandParser = parser.addCommand('analyze');
    commandParser.addFlag('ignore-infos', negatable: false,
        help: 'Ignore any info level issues.');
    parser.addCommand('clean');

    return parser;
  }

  void _usage(ArgParser argParser) {
    _out('usage: ${APP_NAME} <command>');
    _out('A tool to improve visibility into your Dart projects.');
    _out('');
    _out('options:');
    _out(argParser.usage);
    _out('');
    _out('commands:');
    _commands.forEach((name, command) {
      _out('  ${name}: ${command.description}');
      String usage = argParser.commands[name].usage;
      if (usage.isNotEmpty) {
        _out('    ' + usage.split('\n').join('    '));
      }
    });
  }

  void _out(String str) => logger.stdout(str);
}

class ArgError implements Exception {
  final String message;
  ArgError(this.message);
  String toString() => message;
}
