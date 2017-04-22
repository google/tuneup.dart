// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/**
 * A command-line tool to manipulate and inspect your Dart projects.
 */
library tuneup;

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:intl/intl_standalone.dart' as intl;
import 'package:path/path.dart' as path;

import 'src/ansi.dart';
import 'src/check_command.dart';
import 'src/clean_command.dart';
import 'src/common.dart';
import 'src/init_command.dart';
import 'src/logger.dart';
import 'src/stats_command.dart';
import 'src/trim_command.dart';

export 'src/logger.dart' show StandardLogger;

// This version must be updated in tandem with the pubspec version.
const String appVersion = '0.3.0';
const String appName = 'tuneup';

// TODO(devoncarew): fix our use of subcommands

class Tuneup {
  Logger logger;
  Ansi ansi;
  final Map<String, Command> _commands = {};

  Tuneup({this.logger}) {
    ansi = new Ansi(terminalSupportsAnsi());

    _addCommand(new InitCommand());
    _addCommand(new CheckCommand());
    _addCommand(new StatsCommand());
    _addCommand(new TrimCommand());
    _addCommand(new CleanCommand());
  }

  void _addCommand(Command command) {
    _commands[command.name] = command;
  }

  Future processArgs(List<String> args, {Directory directory}) async {
    await intl.findSystemLocale();

    return _processArgs(args, directory: directory).whenComplete(() {
      logger.flush();
    });
  }

  Future _processArgs(List<String> args, {Directory directory}) {
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

    if (options.wasParsed('color')) {
      ansi = new Ansi(options['color']);
    }

    if (logger == null) {
      logger = new StandardLogger(ansi);
    }

    if (options.command == null && options.rest.isNotEmpty) {
      var message = 'Could not find an command named "${options.rest.first}".';
      _out('Error: ${message}');
      return new Future.error(new ArgError(message));
    }

    if (options['version']) {
      _out('${appName} version ${appVersion}');
      return new Future.value();
    }

    if (options['help']) {
      _usage(argParser);
      return new Future.value();
    }

    if (options['directory'] != null) {
      Directory dir = new Directory(options['directory']);
      if (!dir.existsSync()) {
        var message = 'Directory specified does not exist "${directory.path}".';
        _out('Error: ${message}');
        return new Future.error(new ArgError(message));
      }
      directory = dir;
    }

    if (options['verbose']) {
      logger = new VerboseLogger(ansi);
    }

    Project project = new Project(directory, logger, ansi);
    File pubspec = new File(path.join(directory.path, 'pubspec.yaml'));

    Command command;

    if (options.command == null) {
      // No command specified; run 'check'.
      _out("Running the 'check' command (run with --help for a list of "
          "available commands).");
      command = _commands['check'];
    } else {
      command = _commands[options.command.name];
    }

    // TODO(devoncarew): Do we still want this pubspec check?
    // Verify that we are being run from a project directory.
    if (command.name != 'init' && !pubspec.existsSync()) {
      String message =
          'No pubspec.yaml file found. The tuneup command should be run from '
          'the root of a project.';
      _out(message);
      return new Future.error(new ArgError(message));
    }

    return command.execute(project, options.command);
  }

  ArgParser _createArgParser() {
    ArgParser parser = new ArgParser();

    parser.addFlag('help', abbr: 'h', negatable: false, help: 'Help!');
    parser.addFlag('version',
        negatable: false, help: 'Display the application version.');
    parser.addOption('dart-sdk', hide: true, help: 'the path to the sdk');
    parser.addOption('directory', help: 'The project directory to analyze.');
    parser.addFlag('verbose',
        negatable: false,
        abbr: 'v',
        help: 'Display verbose diagnostic output.');
    parser.addFlag('color',
        help: 'Use asni colors when printing messages.',
        defaultsTo: terminalSupportsAnsi());

    // init
    ArgParser commandParser = parser.addCommand('init');
    commandParser.addFlag('override',
        negatable: false, help: 'Force generation of the sample project.');

    // check
    commandParser = parser.addCommand('check');
    commandParser.addFlag('ignore-infos',
        negatable: false, help: 'Ignore any info level issues.');

    // stats
    parser.addCommand('stats');

    // trim
    parser.addCommand('trim');

    // clean
    parser.addCommand('clean');

    return parser;
  }

  void _usage(ArgParser argParser) {
    final String indent = '        ';

    _out('usage: ${appName} <command>');
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
        _out(indent + usage.split('\n').join(indent));
      }
    });
  }

  void _out(String str) {
    logger == null ? print(str) : logger.stdout(str);
  }
}

class ArgError implements Exception {
  final String message;
  ArgError(this.message);
  String toString() => message;
}
