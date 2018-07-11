// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analysis_server_lib/analysis_server_lib.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;

import '../src/common.dart';
import '../tuneup.dart';

class CheckCommand extends TuneupCommand {
  CheckCommand(Tuneup tuneup)
      : super(tuneup, 'check', 'analyze all the source code in the project') {
    argParser.addFlag('ignore-infos',
        negatable: false, help: 'Ignore any info level issues.');
    argParser.addFlag('preview-dart-2',
        help: 'Run the analysis server opt-ed into Dart 2.');
    argParser.addFlag('use-cfe',
        help: 'Run the analysis server using the new common front end.');
    argParser.addFlag('use-fasta-parser',
        help: 'Run the analysis server using the Fasta parser.');
  }

  Future execute(Project project) async {
    Progress progress =
        project.logger.progress('Checking project ${project.name}');

    Stopwatch stopwatch = new Stopwatch()..start();

    List<String> serverArgs = [];

    if (project.logger.isVerbose) {
      serverArgs.add('--internal-print-to-console');
    }

    if (argResults['preview-dart-2']) {
      serverArgs.add('--preview-dart-2');
    }

    if (argResults.wasParsed('use-cfe')) {
      if (argResults['use-cfe']) {
        serverArgs.add('--use-cfe');
      } else {
        serverArgs.add('--no-use-cfe');
      }
    }

    if (argResults.wasParsed('use-fasta-parser')) {
      if (argResults['use-fasta-parser']) {
        serverArgs.add('--use-fasta-parser');
      } else {
        serverArgs.add('--no-use-fasta-parser');
      }
    }

    // init
    AnalysisServer client = await AnalysisServer.create(
      onRead: (String msg) {
        const int max = 140;
        String s = msg.length > max ? '${msg.substring(0, max)}...' : msg;
        project.trace('<-- $s');
      },
      onWrite: (String msg) {
        project.trace('[--> $msg]');
      },
      sdkPath: project.sdkPath,
      serverArgs: serverArgs,
      clientId: appName,
      clientVersion: appVersion,
      //vmArgs: ['--preview-dart-2'],
    );

    Completer completer = new Completer();
    client.processCompleter.future.then((int code) {
      if (!completer.isCompleted) {
        completer.completeError('analysis exited early (exit code $code)');
      }
    });

    await client.server.onConnected.first.timeout(new Duration(seconds: 10));

    bool hadServerError = false;

    // handle errors
    client.server.onError.listen((ServerError error) {
      StackTrace trace = error.stackTrace == null
          ? null
          : new StackTrace.fromString(error.stackTrace);

      project.logger.stderr('${error}');
      if (trace != null) {
        project.logger.stderr('${trace.toString().trim()}');
      }

      hadServerError = true;
    });

    client.server.setSubscriptions(['STATUS']);
    client.server.onStatus.listen((ServerStatus status) {
      if (status.analysis == null) return;

      if (!status.analysis.isAnalyzing) {
        // notify finished
        if (!completer.isCompleted) {
          completer.complete(true);
        }
        client.dispose();
      }
    });

    Map<String, List<AnalysisError>> errorMap = new Map();
    client.analysis.onErrors.listen((AnalysisErrors e) {
      errorMap[e.file] = e.errors;
    });

    String analysisRoot = path.canonicalize(project.dir.absolute.path);
    client.analysis.setAnalysisRoots([analysisRoot], []);

    // wait for finish
    try {
      await completer.future;
    } catch (error, st) {
      progress.cancel();

      project.logger.stderr('${error}');
      project.logger.stderr('${st}');

      return new ExitCode(1);
    }

    progress.finish();

    // sort, filter, print errors
    List<String> sources = errorMap.keys.toList();
    List<AnalysisError> errors =
        sources.map((String key) => errorMap[key]).fold([], (List a, List b) {
      a.addAll(b);
      return a;
    });

    // Don't show todos.
    errors.removeWhere((e) => e.code == 'todo');

    // Optionally filter out infos.
    bool ignoreInfos = argResults == null ? false : argResults['ignore-infos'];
    int ignoredCount = 0;
    if (ignoreInfos) {
      List<AnalysisError> newErrors =
          errors.where((e) => e.severity != 'INFO').toList();
      ignoredCount = errors.length - newErrors.length;
      errors = newErrors;
    }

    // sort by severity, file, offset
    errors.sort((AnalysisError one, AnalysisError two) {
      int comp = _severityLevel(two.severity) - _severityLevel(one.severity);
      if (comp != 0) return comp;

      if (one.location.file != two.location.file) {
        return one.location.file.compareTo(two.location.file);
      }

      return one.location.offset - two.location.offset;
    });

    final Ansi ansi = project.logger.ansi;

    Map<String, String> colorMap = {
      'ERROR': ansi.red,
      'WARNING': ansi.yellow,
    };

    if (errors.isNotEmpty) {
      project.print('');

      errors.forEach((AnalysisError e) {
        String issueColor = colorMap[e.severity] ?? '';

        String severity = e.severity.toLowerCase();

        String location = e.location.file;
        if (location.startsWith(analysisRoot)) {
          location = location.substring(analysisRoot.length + 1);
        }
        location =
            '$location:${e.location.startLine}:${e.location.startColumn}';

        String message = e.message;
        if (message.endsWith('.')) {
          message = message.substring(0, message.length - 1);
        }

        String code = e.code;

        project.print('  ${issueColor}$severity${ansi.none} ${ansi.bullet} '
            '${ansi.bold}$message${ansi.none} at $location ${ansi
                .bullet} ($code)');
      });

      project.print('');
    }

    String ignoreMessage = '';
    if (ignoredCount > 0) {
      ignoreMessage = ' (${formatNumber(ignoredCount)} ${pluralize(
          "issue", ignoredCount)} ignored)';
    }

    final NumberFormat secondsFormat = new NumberFormat('0.0');
    double seconds = stopwatch.elapsedMilliseconds / 1000.0;
    project.print(
        '${errors.isEmpty ? "No" : formatNumber(errors.length)} ${pluralize(
            "issue", errors.length)} '
        'found; analyzed ${formatNumber(sources.length)} source ${pluralize(
            "file", sources.length)} '
        'in ${secondsFormat.format(seconds)}s${ignoreMessage}.');

    // return the results
    return (errors.isEmpty && !hadServerError)
        ? new Future.value()
        : new Future.error(new ExitCode(1));
  }
}

int _severityLevel(String severity) {
  if (severity == 'ERROR') return 2;
  if (severity == 'WARNING') return 1;
  return 0;
}
