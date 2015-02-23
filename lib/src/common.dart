// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library tuneup.common;

import 'dart:async';
import 'dart:io';

import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart' as yaml;

List cliArgs = [];

final bool isWindows = Platform.isWindows;

final String pathSep = isWindows ? r'\' : '/';

abstract class Command {
  final String name;
  final String description;

  Command(this.name, this.description);

  Future execute(Project project, [args]);
}

class Project {
  final List<String> PUB_FOLDERS = [
    'benchmark', 'bin', 'example', 'lib', 'test', 'tool', 'web'
  ];

  final Directory dir;
  final CliLogger logger;

  Project(this.dir, this.logger);

  String get name {
    if (pubspec.containsKey('name'))  {
      return pubspec['name'];
    } else {
      return path.basename(dir.path);
    }
  }

  String get sdkPath => cli_util.getSdkDir(cliArgs).path;

  String get packagePath => 'packages';

  yaml.YamlMap get pubspec {
    return yaml.loadYaml(
        new File(path.join(dir.path, 'pubspec.yaml')).readAsStringSync());
  }

  List<File> getSourceFiles({List<String> extensions: const ['dart']}) {
    List<File> files = [];

    _getFiles(files, dir, recursive: false, extensions: extensions);

    PUB_FOLDERS.forEach((name) {
      if (FileSystemEntity.isDirectorySync(path.join(dir.path, name))) {
        Directory other = new Directory(path.join(dir.path, name));
        _getFiles(files, other, recursive: true, extensions: extensions);
      }
    });

    return files;
  }

  void print(o) => logger.stdout('${o}');

  void _getFiles(List<File> files, Directory dir,
      {bool recursive: false, List<String> extensions}) {
    dir.listSync(recursive: recursive, followLinks: false).forEach((entity) {
      if (entity is File) {
        String ext = getFileExtension(entity.path).toLowerCase();
        if (extensions.contains(ext)) files.add(entity);
      }
    });
  }
}

class ExitCode {
  final int code;
  ExitCode(this.code);
}

class CliLogger {
  const CliLogger();

  void stdout(String message) => print(message);
  void stderr(String message) => print(message);
}

String pluralize(String word, int count) => count == 1 ? word : '${word}s';

String format(int i) {
  String str = '${i}';
  int pos = str.length - 3;

  while (pos > 0) {
    str = str.substring(0, pos) + ',' + str.substring(pos);
    pos -= 3;
  }

  return str;
}

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
    } else if (contents[index - 1] == '\r'){
      return '\r\n';
    } else {
      return '\n';
    }
  }

  return isWindows ? '\r\n' : '\n';
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
    {List<String> arguments : const [],
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
    {List<String> arguments : const [],
     String workingDirectory}) {
  ProcessResult result = Process.runSync(
      executable, arguments, workingDirectory: workingDirectory);

  print(result.stdout.trim());
  
  if (result.stderr != null && !result.stderr.isEmpty) {
    print(result.stderr);
  }

  if (result.exitCode != 0) {
    throw "${executable} failed with a return code of ${result.exitCode}";
  }
}
