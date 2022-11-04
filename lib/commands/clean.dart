// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../src/common.dart';
import '../tuneup.dart';

class CleanCommand extends TuneupCommand {
  CleanCommand(Tuneup tuneup)
      : super(
            tuneup, 'clean', 'clean the project - remove the build/ directory');

  @override
  Future execute(Project project) {
    Directory buildDir = Directory(path.join(project.dir.path, 'build'));

    if (buildDir.existsSync()) {
      project.print('Deleting ${path.basename(buildDir.path)}/.');
      return buildDir.delete(recursive: true);
    } else {
      return Future.value();
    }
  }
}
