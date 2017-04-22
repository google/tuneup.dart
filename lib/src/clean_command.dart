// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'common.dart';

class CleanCommand extends Command {
  CleanCommand()
      : super('clean', 'clean the project - remove the build/ directory');

  Future execute(Project project, [args]) {
    Directory buildDir = new Directory(path.join(project.dir.path, 'build'));

    if (buildDir.existsSync()) {
      project.print('Deleting ${path.basename(buildDir.path)}/.');
      return buildDir.delete(recursive: true);
    } else {
      return new Future.value();
    }
  }
}
