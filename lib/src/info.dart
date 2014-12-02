// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library tuneup.info;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'common.dart';

// TODO: direct dependencies

// TODO: indirect dependencies

// TODO: breakdown of dart/html/...

// TODO: breakdown of which lines in what dirs

class InfoCommand extends Command {
  InfoCommand() : super('info',
      'display metadata and statistics about the project');

  Future execute(Project project, [args]) {
    YamlMap pubspec = project.pubspec;

    String version = pubspec.containsKey('version') ? pubspec['version'] : '-';

    project.print("Package '${project.name}', version ${version}.");

    List<File> files = project.getSourceFiles();

    Map _stats = {};

    files.forEach((file) {
      String ext = path.extension(file.path);
      if (ext.startsWith('.')) ext = ext.substring(1);
      if (!_stats.containsKey(ext)) {
        _stats[ext] = new _Stats();
      }
      _stats[ext].files++;
      _stats[ext].lines += _lineCount(file);
    });

    _Stats all = _stats.values.reduce((a, b)
        => new _Stats(a.files + b.files, a.lines + b.lines));

    project.print('${all.files} source files, ${all.lines} lines of code.');

    return new Future.value();
  }
}

class _Stats {
  int files;
  int lines;

  _Stats([this.files = 0, this.lines = 0]);
}

int _lineCount(File file) {
  String str = file.readAsStringSync();
  return str.split('\n').where((l) => l.trim().isNotEmpty).length;
}
