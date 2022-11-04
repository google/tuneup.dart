// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../src/common.dart';
import '../tuneup.dart';

class InitCommand extends TuneupCommand {
  InitCommand(Tuneup tuneup) : super(tuneup, 'init', 'create a new project') {
    argParser.addFlag('override',
        negatable: false, help: 'Force generation of the sample project.');
  }

  @override
  Future execute(Project project) {
    if (!argResults!['override'] && !_isDirEmpty(project.dir)) {
      return Future.error('The current directory is not empty. Please '
          'create a new project directory, or use --override to force '
          'generation into the current directory.');
    }

    // Validate and normalize the project name.
    String projectName = path.basename(project.dir.path);
    if (_validateName(projectName) != null) {
      return Future.error(_validateName(projectName)!);
    }
    projectName = _normalizeProjectName(projectName);

    _writeFile(project, '.gitignore', _gitignore, projectName);
    _writeFile(project, 'bin/helloworld.dart', _helloworld, projectName);
    _writeFile(project, 'pubspec.yaml', _pubspec, projectName);

    project.print("running bin/helloworld.dart...");
    project.print('');
    runDartScript('bin/helloworld.dart', workingDirectory: project.dir.path);

    return Future.value();
  }
}

final String _gitignore = """
.DS_Store
.pub
build/
packages
pubspec.lock
""";

final String _helloworld = """
void main() {
  print('hello world!');
}
""";

final String _pubspec = """
name: {{projectName}}
version: 0.0.1
#description: todo:
#author: First Last <username@example.com>
#homepage: example.com
environment:
  sdk: '>=1.0.0 <2.0.0'
#dependencies:
#  foo: any
#dev_dependencies:
#  unittest: any
""";

void _writeFile(
    Project project, String filename, String contents, String projectName) {
  contents = contents.replaceAll('{{projectName}}', projectName);
  File file = File(path.join(project.dir.path, filename));
  if (!file.parent.existsSync()) file.parent.createSync();
  file.writeAsStringSync(contents);
  project.print('Created $filename.');
}

/// Return true if there are any non-symlinked, non-hidden sub-directories in
/// the given directory.
bool _isDirEmpty(Directory dir) {
  isHiddenDir(dir) => path.basename(dir.path).startsWith('.');

  return dir
      .listSync(followLinks: false)
      .whereType<Directory>()
      .where((entity) => !isHiddenDir(entity))
      .isEmpty;
}

String? _validateName(String projectName) {
  if (projectName.contains(' ')) {
    return "The project name cannot contain spaces.";
  }

  if (!projectName.startsWith(RegExp(r'[A-Za-z]'))) {
    return "The project name must start with a letter.";
  }

  // Project name is valid.
  return null;
}

/// Convert a directory name into a reasonably legal pub package name.
String _normalizeProjectName(String name) {
  name = name.replaceAll('-', '_');

  // Strip any extension (like .dart).
  if (name.contains('.')) {
    name = name.substring(0, name.indexOf('.'));
  }

  return name;
}
