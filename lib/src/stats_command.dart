// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library tuneup.info_command;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'common.dart';

class StatsCommand extends Command {
  StatsCommand() : super('stats',
      'display metadata and statistics about the project');

  Future execute(Project project, [args]) {
    Map pubspec = project.pubspec;

    String version = pubspec.containsKey('version') ? pubspec['version'] : '-';

    project.print("Package '${project.name}', version ${version}.");

    List<File> files = project.getSourceFiles(extensions: ['dart', 'html', 'css']);

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

    _Stats all = _stats.values.reduce(
      (a, b) => new _Stats(a.files + b.files, a.lines + b.lines)
    );

    // "Found 288 Dart files and 44,863 lines of code."
    // TODO: print a breakdown by type
    project.print('Found ${format(all.files)} source files and '
        '${format(all.lines)} lines of code.');

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
  return str.split('\n').where((String line) {
    line = line.trim();
    if (line.isEmpty) return false;
    if (line.startsWith('//') || line.startsWith('* ') || line.startsWith('*/') || line.startsWith('/*')) {
      return false;
    }
    return true;
  }).length;
}
