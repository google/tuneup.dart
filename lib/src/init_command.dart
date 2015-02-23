// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library tuneup.init_command;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'common.dart';

// TODO: support an optional --dest arg?

class InitCommand extends Command {
  InitCommand() : super('init', 'create a new project');

  Future execute(Project project, [args]) {
    if (args== null) args = {};

    if (!args['override'] && !_isDirEmpty(project.dir)) {
      return new Future.error('The current directory is not empty. Please '
          'create a new project directory, or use --override to force '
          'generation into the current directory.');
    }

    // Validate and normalize the project name.
    String projectName = path.basename(project.dir.path);
    if (_validateName(projectName) != null) {
      return new Future.error(_validateName(projectName));
    }
    projectName = _normalizeProjectName(projectName);

    _writeFile(project, '.gitignore', _gitignore, projectName);
    _writeFile(project, 'bin/helloworld.dart', _helloworld, projectName);
    _writeFile(project, 'pubspec.yaml', _pubspec, projectName);

    project.print("running bin/helloworld.dart...");
    project.print('');
    runDartScript('bin/helloworld.dart', workingDirectory: project.dir.path);

    return new Future.value();
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

void _writeFile(Project project, String filename, String contents,
    String projectName) {
  contents = contents.replaceAll('{{projectName}}', projectName);
  File file = new File(path.join(project.dir.path, filename));
  if (!file.parent.existsSync()) file.parent.createSync();
  file.writeAsStringSync(contents);
  project.print('Created ${filename}.');
}

/**
 * Return true if there are any non-symlinked, non-hidden sub-directories in
 * the given directory.
 */
bool _isDirEmpty(Directory dir) {
  var isHiddenDir = (dir) => path.basename(dir.path).startsWith('.');

  return dir.listSync(followLinks: false)
      .where((entity) => entity is Directory)
      .where((entity) => !isHiddenDir(entity))
      .isEmpty;
}

String _validateName(String projectName) {
  if (projectName.contains(' ')) {
    return "The project name cannot contain spaces.";
  }

  if (!projectName.startsWith(new RegExp(r'[A-Za-z]'))) {
    return "The project name must start with a letter.";
  }

  // Project name is valid.
  return null;
}

/**
 * Convert a directory name into a reasonably legal pub package name.
 */
String _normalizeProjectName(String name) {
  name = name.replaceAll('-', '_');

  // Strip any extension (like .dart).
  if (name.contains('.')) {
    name = name.substring(0, name.indexOf('.'));
  }

  return name;
}
