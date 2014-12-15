// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library tuneup.analyze;

import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/error.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/sdk_io.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:analyzer/src/generated/java_io.dart';

import 'common.dart';

class AnalyzeCommand extends Command {
  AnalyzeCommand() : super('analyze',
      'analyze all the source code in the project - fail if there are any errors');

  Future execute(Project project, [args]) {
    bool ignoreInfos = args['ignore-infos'];

    Stopwatch stopwatch = new Stopwatch()..start();

    DartSdk sdk = new DirectoryBasedDartSdk(new JavaFile(project.sdkPath));
    AnalysisContext context = AnalysisEngine.instance.createAnalysisContext();
    context.analysisOptions = new AnalysisOptionsImpl()..cacheSize = 512;
    List<UriResolver> resolvers = [
        new DartUriResolver(sdk),
        new FileUriResolver(),
        new PackageUriResolver([new JavaFile(project.packagePath)])];
    context.sourceFactory = new SourceFactory(resolvers);
    AnalysisEngine.instance.logger = new _Logger();

    project.print('Analyzing ${project.name}...');

    List<Source> sources = [];
    ChangeSet changeSet = new ChangeSet();
    for (File file in project.getSourceFiles()) {
      JavaFile sourceFile = new JavaFile(file.path);
      Source source = new FileBasedSource.con2(sourceFile.toURI(), sourceFile);
      sources.add(source);
      changeSet.addedSource(source);
    }
    context.applyChanges(changeSet);

    List<AnalysisErrorInfo> errorInfos = [];

    for (Source source in sources) {
      context.computeErrors(source);
      errorInfos.add(context.getErrors(source));
    }

    stopwatch.stop();

    List<_Error> errors = errorInfos
      .expand((AnalysisErrorInfo info) {
        return info.errors.map((error)
            => new _Error(error, info.lineInfo, project.dir.path));
      })
      .where((_Error error) => error.errorType != ErrorType.TODO)
      .toList();

    int ignoredCount = 0;

    if (ignoreInfos) {
      List newErrors = errors.where(
          (e) => e.severity != ErrorSeverity.INFO.ordinal).toList();
      ignoredCount = errors.length - newErrors.length;
      errors = newErrors;
    }

    errors.sort();

    var seconds = (stopwatch.elapsedMilliseconds ~/ 100) * 100 / 1000;
    project.print(
        '${errors.isEmpty ? "No" : errors.length} ${pluralize("issue", errors.length)} '
        'found; analyzed ${sources.length} source ${pluralize("file", sources.length)} '
        'in ${seconds}s.');

    if (ignoredCount > 0) {
      project.print('(${ignoredCount} ${pluralize("issue", ignoredCount)} ignored)');
    }

    if (errors.isNotEmpty) {
      project.print('');
      errors.forEach((e) => project.print('[${e.severityName}] ${e.description}'));
    }

    return errors.isEmpty ? new Future.value() : new Future.error(new ExitCode(1));
  }
}

class _Error implements Comparable {
  final AnalysisError error;
  final LineInfo lineInfo;
  final String projectPath;

  _Error(this.error, this.lineInfo, this.projectPath);

  ErrorType get errorType => error.errorCode.type;
  int get severity => error.errorCode.errorSeverity.ordinal;
  String get severityName => error.errorCode.errorSeverity.displayName;
  String get message => error.message;
  String get description => '${message} at ${location}, line ${line}.';
  int get line => lineInfo.getLocation(error.offset).lineNumber;

  String get location {
    String path = error.source.fullName;
    if (path.startsWith(projectPath)) {
      path = path.substring(projectPath.length + 1);
    }
    return path;
  }

  int compareTo(_Error other) {
    if (severity == other.severity) {
      int cmp = error.source.fullName.compareTo(other.error.source.fullName);
      return cmp == 0 ? line - other.line : cmp;
    } else {
      return other.severity - severity;
    }
  }

  String toString() => '[${severityName}] ${description}';
}

class _Logger extends Logger {
  void logError(String message) => stderr.writeln(message);
  void logError2(String message, dynamic exception) => stderr.writeln(message);
  void logInformation(String message) { }
  void logInformation2(String message, dynamic exception) { }
}
