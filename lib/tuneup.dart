// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/// A command-line tool to manipulate and inspect your Dart projects.
library tuneup;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:cli_util/cli_util.dart';
import 'package:tuneup/commands/clean.dart';
import 'package:tuneup/commands/init.dart';
import 'package:tuneup/commands/stats.dart';
import 'package:tuneup/commands/trim.dart';

import 'commands/check.dart';
import 'src/common.dart';

// This version must be updated in tandem with the pubspec version.
const String appVersion = '0.3.9';
const String appName = 'tuneup';

class Tuneup extends CommandRunner<void> {
  Logger? logger;
  late Project project;

  Tuneup({this.logger})
      : super(
          appName,
          'A tool to improve visibility into your Dart projects.',
        ) {
    argParser.addFlag('version',
        negatable: false, help: 'Display the application version.');
    argParser.addOption('dart-sdk', help: 'the path to the sdk');
    argParser.addOption('directory', help: 'The project directory to analyze.');
    argParser.addFlag('verbose',
        negatable: false,
        abbr: 'v',
        help: 'Display verbose diagnostic output.');
    argParser.addFlag('color',
        help: 'Use ansi colors when printing messages.',
        defaultsTo: Ansi.terminalSupportsAnsi);

    addCommand(InitCommand(this));
    addCommand(CheckCommand(this));
    addCommand(StatsCommand(this));
    addCommand(TrimCommand(this));
    addCommand(CleanCommand(this));
  }

  @override
  Future<void> run(Iterable<String> args, {Directory? directory}) async {
    ArgResults results = args.isEmpty ? parse(['check']) : parse(args);

    Ansi? ansi;
    if (results.wasParsed('color')) {
      ansi = Ansi(results['color']);
    }

    logger ??= Logger.standard(ansi: ansi);

    if (results['version']) {
      _out('$appName version $appVersion');
      return Future.value();
    }

    if (results['directory'] != null) {
      Directory dir = Directory(results['directory']);
      if (!dir.existsSync()) {
        String message = 'Directory specified does not exist "${dir.path}".';
        _out('Error: $message');
        throw UsageException(message, usage);
      }
      directory = dir;
    }

    String sdkPath =
        results.wasParsed('dart-sdk') ? results['dart-sdk'] : getSdkPath();

    directory ??= Directory.current;

    if (results['verbose']) {
      logger = Logger.verbose(ansi: ansi);
    }

    project = Project(directory, sdkPath, logger!);

    return runCommand(results);
  }

  void _out(String str) {
    logger == null ? print(str) : logger!.stdout(str);
  }
}
