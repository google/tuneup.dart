// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:analyzer/file_system/file_system.dart' as analysisFile
    show File;
import 'package:analyzer/file_system/file_system.dart' show ResourceProvider;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/source/analysis_options_provider.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:quiver/pattern.dart' show Glob;
import 'package:yaml/yaml.dart' as yaml;

import 'ansi.dart';
import 'logger.dart';

final String pathSep = Platform.isWindows ? r'\' : '/';

abstract class Command {
  final String name;
  final String description;

  Command(this.name, this.description);

  Future execute(Project project, [args]);
}

class Project {
  final List<String> kPubFolders = [
    'benchmark',
    'bin',
    'example',
    'lib',
    'test',
    'tool',
    'web'
  ];

  final Directory dir;
  final StandardLogger logger;
  final Ansi ansi;

  List<Glob> _excludes = [];

  Project(this.dir, this.logger, this.ansi) {
    ResourceProvider resourceProvider = PhysicalResourceProvider.INSTANCE;
    analysisFile.File file =
        resourceProvider.getFile(AnalysisEngine.ANALYSIS_OPTIONS_FILE);
    if (!file.exists) {
      file =
          resourceProvider.getFile(AnalysisEngine.ANALYSIS_OPTIONS_YAML_FILE);
    }
    if (file.exists) {
      AnalysisOptionsProvider analysisOptions = new AnalysisOptionsProvider();
      Map options = analysisOptions.getOptionsFromFile(file);

      if (options != null && options.isNotEmpty) {
        // Handle excludes.
        // analyzer:
        //   exclude:
        //     - test/data/*
        dynamic analyzerSection = options['analyzer'];
        if (analyzerSection is Map) {
          dynamic excludes = analyzerSection['exclude'];
          if (excludes is List) {
            _excludes.addAll(excludes
                .where((ex) => ex is String)
                .map((String st) => new Glob(st)));
          }
        }
      }
    }
  }

  String get name {
    if (pubspec.containsKey('name')) {
      return pubspec['name'];
    } else {
      return path.basename(dir.path);
    }
  }

  String get sdkPath => path.dirname(path.dirname(Platform.resolvedExecutable));

  String get packagePath => path.join(dir.path, 'packages');

  Directory get packageDir => new Directory(packagePath);

  File get packagesFile => new File(path.join(dir.path, '.packages'));

  yaml.YamlMap get pubspec {
    return yaml.loadYaml(
        new File(path.join(dir.path, 'pubspec.yaml')).readAsStringSync());
  }

  List<File> getSourceFiles({List<String> extensions: const ['dart']}) {
    List<File> files = [];

    _getFiles(files, dir, recursive: false, extensions: extensions);

    kPubFolders.forEach((name) {
      if (FileSystemEntity.isDirectorySync(path.join(dir.path, name))) {
        Directory other = new Directory(path.join(dir.path, name));
        _getFiles(files, other, recursive: true, extensions: extensions);
      }
    });

    return files;
  }

  void error(o) => logger.stderr('${o}');

  void print(o) => logger.stdout('${o}');

  void trace(o) => logger.trace('${o}');

  void _getFiles(List<File> files, Directory dir,
      {bool recursive: false, List<String> extensions}) {
    if (path.basename(dir.path).startsWith('.')) return;

    String projectPath = this.dir.path;
    if (!projectPath.endsWith(Platform.pathSeparator)) {
      projectPath += Platform.pathSeparator;
    }

    dir.listSync(followLinks: false).forEach((entity) {
      if (entity is File) {
        String shortPath = entity.path;
        if (shortPath.startsWith(projectPath)) {
          shortPath = shortPath.substring(projectPath.length);
        }

        for (Glob glob in _excludes) {
          if (glob.hasMatch(shortPath)) return;
        }

        String ext = getFileExtension(entity.path).toLowerCase();
        if (extensions.contains(ext)) files.add(entity);
      } else if (entity is Directory && recursive) {
        _getFiles(files, entity, recursive: recursive, extensions: extensions);
      }
    });
  }
}

class ExitCode {
  final int code;
  ExitCode(this.code);
}

String pluralize(String word, int count) => count == 1 ? word : '${word}s';

final NumberFormat kNumberFormat = new NumberFormat.decimalPattern();

String formatNumber(int i) => kNumberFormat.format(i);

String getFileExtension(String path) {
  int index = path.lastIndexOf(pathSep);
  if (index != -1) path = path.substring(index + 1);

  index = path.lastIndexOf('.');
  return index != -1 ? path.substring(index + 1) : '';
}

String discoverEol(String contents) {
  int index = contents.indexOf('\n');

  if (index != -1) {
    if (index == 0) {
      return '\n';
    } else if (contents[index - 1] == '\r') {
      return '\r\n';
    } else {
      return '\n';
    }
  }

  return Platform.isWindows ? '\r\n' : '\n';
}

String relativePath(File file) {
  String p = file.absolute.path;
  String current = Directory.current.absolute.path;

  if (p.startsWith(current)) {
    return p.substring(current.length);
  } else {
    return file.path;
  }
}

/**
 * Run the given Dart script in a new process.
 */
void runDartScript(String script,
    {List<String> arguments: const [],
    String packageRoot,
    String workingDirectory}) {
  List<String> args = [];

  if (packageRoot != null) {
    args.add('--package-root=${packageRoot}');
  }

  args.add(script);
  args.addAll(arguments);

  runProcess('dart', arguments: args, workingDirectory: workingDirectory);
}

/**
 * Run the given executable, with optional arguments and working directory.
 */
void runProcess(String executable,
    {List<String> arguments: const [], String workingDirectory}) {
  ProcessResult result = Process.runSync(executable, arguments,
      workingDirectory: workingDirectory);

  print(result.stdout.trim());

  if (result.stderr != null && !result.stderr.isEmpty) {
    print(result.stderr);
  }

  if (result.exitCode != 0) {
    throw "${executable} failed with a return code of ${result.exitCode}";
  }
}
