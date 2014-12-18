// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library integration_test;

import 'dart:io';

import 'package:tuneup/tuneup.dart';
import 'package:unittest/unittest.dart';

void main() => defineTests();

void defineTests() {
  group('integration tests', () {
    final Directory foo = new Directory('foo');
    _Logger logger;

    setUp(() {
      if (foo.existsSync()) foo.deleteSync(recursive: true);
      foo.createSync();
      logger = new _Logger();
    });

    tearDown(() {
      try { foo.deleteSync(recursive: true); }
      catch (e) { }
    });

    test('no args', () {
      Tuneup tuneup = new Tuneup(logger);
      return tuneup.processArgs([], directory: foo).then((_) {
        expect(logger.out, contains('A tool to improve visibility into your Dart projects.'));
        expect(logger.out, contains('commands:'));
        expect(logger.err, isEmpty);
      });
    });

    test('--help', () {
      Tuneup tuneup = new Tuneup(logger);
      return tuneup.processArgs(['--help'], directory: foo).then((_) {
        expect(logger.out, contains('A tool to improve visibility into your Dart projects.'));
        expect(logger.out, contains('commands:'));
        expect(logger.err, isEmpty);
      });
    });

    test('--version', () {
      Tuneup tuneup = new Tuneup(logger);
      return tuneup.processArgs(['--version'], directory: foo).then((_) {
        expect(logger.out, contains('tuneup version '));
        expect(logger.err, isEmpty);
      });
    });

    test('init', () {
      Tuneup tuneup = new Tuneup(logger);
      return tuneup.processArgs(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      });
    });

    test('stats', () {
      Tuneup tuneup = new Tuneup(logger);
      return tuneup.processArgs(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      }).then((_) {
        return tuneup.processArgs(['stats'], directory: foo).then((_) {
          expect(logger.out, contains('1 source files, 3 lines of code.'));
          expect(logger.err, isEmpty);
        });
      });
    });

    test('analyze', () {
      Tuneup tuneup = new Tuneup(logger);
      return tuneup.processArgs(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      }).then((_) {
        return tuneup.processArgs(['analyze'], directory: foo);
      }).then((_) {
        expect(logger.out, contains('No issues found; analyzed 1 source file in'));
        expect(logger.err, isEmpty);
      });
    });

    test('clean', () {
      Tuneup tuneup = new Tuneup(logger);
      return tuneup.processArgs(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      }).then((_) {
        new Directory('foo/build').createSync();
        return tuneup.processArgs(['clean'], directory: foo);
      }).then((_) {
        print(logger.out);
        expect(logger.out, contains('Deleting build'));
        expect(logger.err, isEmpty);
      });
    });
  });
}

class _Logger implements CliLogger {
  StringBuffer _out = new StringBuffer();
  StringBuffer _err = new StringBuffer();

  void stdout(String message) => _out.writeln(message);
  void stderr(String message) => _err.writeln(message);

  String get out => _out.toString();
  String get err => _err.toString();
}
