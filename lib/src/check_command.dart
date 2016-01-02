// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library tuneup.check_command;

import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart';
import 'package:analyzer/file_system/file_system.dart' hide File;
import 'package:analyzer/file_system/file_system.dart' as analysisFile show File;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/source/analysis_options_provider.dart';
import 'package:analyzer/source/sdk_ext.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/error.dart';
import 'package:analyzer/src/generated/java_io.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/sdk_io.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:analyzer/src/task/options.dart';
import 'package:package_config/discovery.dart' as pkgDiscovery;
import 'package:package_config/packages.dart' show Packages;
import 'package:path/path.dart' as p;

import 'common.dart';

// TODO: Support strong mode?

class CheckCommand extends Command {
  CheckCommand() : super('check',
      'analyze all the source code in the project - fail if there are any errors');

  Future execute(Project project, [args]) {
    bool ignoreInfos = args == null ? false : args['ignore-infos'];

    Stopwatch stopwatch = new Stopwatch()..start();

    AnalysisEngine.instance.taskManager;

    DartSdk sdk = new DirectoryBasedDartSdk(new JavaFile(project.sdkPath));
    AnalysisContext context = AnalysisEngine.instance.createAnalysisContext();
    context.analysisOptions = new AnalysisOptionsImpl()..cacheSize = 512;
    AnalysisEngine.instance.processRequiredPlugins();

    List<UriResolver> resolvers = [
      new DartUriResolver(sdk)
    ];

    Packages packages;

    if (project.packagesFile.existsSync()) {
      packages = _discoverPackagespec(project.dir);
      resolvers.add(
        new SdkExtUriResolver(_createPackageFilePackageMap(packages)));
    } else if (project.packageDir.existsSync()) {
      new PackageUriResolver([new JavaFile(project.packagePath)]);
      resolvers.add(
        new SdkExtUriResolver(_createPackagesFolderPackageMap(project)));
    }

    resolvers.add(new FileUriResolver());

    context.sourceFactory = new SourceFactory(resolvers, packages);
    AnalysisEngine.instance.logger = new _Logger();

    _processAnalysisOptions(context);

    project.print('Checking project ${project.name}...');

    List<Source> sources = [];
    ChangeSet changeSet = new ChangeSet();
    for (File file in project.getSourceFiles()) {
      JavaFile sourceFile = new JavaFile(file.path);
      Source source = new FileBasedSource(sourceFile, sourceFile.toURI());
      Uri uri = context.sourceFactory.restoreUri(source);
      if (uri != null) source = new FileBasedSource(sourceFile, uri);
      sources.add(source);
      changeSet.addedSource(source);
    }
    context.applyChanges(changeSet);

    // Ensure that the analysis engine performs all remaining work.
    AnalysisResult result = context.performAnalysisTask();
    while (result.hasMoreWork) {
      result = context.performAnalysisTask();
    }

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


  Map<String, List<Folder>> _createPackageFilePackageMap(Packages packages) {
    Map<String, List<Folder>> m = {};
    Map packageMap = packages.asMap();

    for (String name in packageMap.keys) {
      Uri uri = packageMap[name];
      if (uri.scheme == 'file') {
        String file = uri.path;
        m[name] = [PhysicalResourceProvider.INSTANCE.getFolder(file)];
      }
    }

    return m;
  }

  Map<String, List<Folder>> _createPackagesFolderPackageMap(Project project) {
    Map<String, List<Folder>> m = {};

    for (FileSystemEntity entity in project.packageDir.listSync(followLinks: false)) {
      if (entity is Link) {
        String name = p.basename(entity.path);
        String target = entity.targetSync();
        m[name] = [PhysicalResourceProvider.INSTANCE.getFolder(target)];
      }
    }

    return m;
  }

  /// Return discovered packagespec or `null` if none is found.
  Packages _discoverPackagespec(Directory dir) {
    try {
      Packages packages =
          pkgDiscovery.findPackagesFromFile(new Uri.directory(dir.path));
      if (packages != Packages.noPackages) return packages;
    } catch (_) {
      // Ignore and fall through to null.
    }

    return null;
  }

  void _processAnalysisOptions(AnalysisContext context) {
    String name = AnalysisEngine.ANALYSIS_OPTIONS_FILE;
    analysisFile.File file = PhysicalResourceProvider.INSTANCE.getFile(name);
    if (!file.exists) return;

    AnalysisOptionsProvider analysisOptions = new AnalysisOptionsProvider();
    Map options = analysisOptions.getOptionsFromFile(file);

    if (options == null || options.isEmpty) return;

    // Handle options processors.
    List processors = AnalysisEngine.instance.optionsPlugin.optionsProcessors;
    processors.forEach((processor) => processor.optionsProcessed(context, options));
    configureContextOptions(context, options);
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
  void logError(String message, [exception]) => stderr.writeln(message);
  void logError2(String message, dynamic exception) => stderr.writeln(message);
  void logInformation(String message, [exception]) { }
  void logInformation2(String message, dynamic exception) { }
}
