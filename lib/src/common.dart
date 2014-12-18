// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library tuneup.common;

import 'dart:async';
import 'dart:io';

import 'package:grinder/grinder.dart' as grinder;
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart' as yaml;

export 'package:yaml/yaml.dart' show YamlMap;

List cliArgs = [];

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

  String get sdkPath => grinder.getSdkDir(cliArgs).path;

  String get packagePath => 'packages';

  yaml.YamlMap get pubspec {
    return yaml.loadYaml(
        new File(path.join(dir.path, 'pubspec.yaml')).readAsStringSync());
  }

  // TODO: add params to choose the types of files
  List<File> getSourceFiles() {
    List<File> files = [];

    _getFiles(files, dir, recursive: false);

    PUB_FOLDERS.forEach((name) {
      if (FileSystemEntity.isDirectorySync(path.join(dir.path, name))) {
        Directory other = new Directory(path.join(dir.path, name));
        _getFiles(files, other, recursive: true);
      }
    });

    return files;
  }

  void print(Object o) => logger.stdout('${o}');

  void _getFiles(List<File> files, Directory dir, {bool recursive: false}) {
    dir.listSync(recursive: recursive, followLinks: false).forEach((entity) {
      if (entity is File) {
        if (_isSourceFile(entity)) {
          files.add(entity);
        }
      }
    });
  }

  bool _isSourceFile(File file) {
    // TODO:
    return file.path.endsWith('.dart') || file.path.endsWith('.html');
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
