// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:io';

import 'package:tuneup/src/common.dart';
import 'package:tuneup/src/logger.dart';
import 'package:tuneup/tuneup.dart';
import 'package:unittest/unittest.dart';

void main() => defineTests();

void defineTests() {
  group('integration', () {
    final Directory foo = new Directory('foo');
    _Logger logger;

    setUp(() {
      if (foo.existsSync()) foo.deleteSync(recursive: true);
      foo.createSync();
      logger = new _Logger();
    });

    tearDown(() {
      try {
        foo.deleteSync(recursive: true);
      } catch (e) {}
    });

    test('no args', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.processArgs(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      }).then((_) {
        _setupPub();
        return tuneup.processArgs(['check'], directory: foo);
      }).then((_) {
        expect(
            logger.out, contains('No issues found; analyzed 1 source file in'));
        expect(logger.err, isEmpty);
      });
    });

    test('bad command', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.processArgs(['foo_command'], directory: foo).then((_) {
        fail('expected exception');
      }).catchError((e) {
        expect(logger.out, contains('Could not find an command named'));
      });
    });

    test('bad arg', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.processArgs(['--foo', 'bar'], directory: foo).then((_) {
        fail('should have thrown');
      }).catchError((e) {
        expect(e is ArgError, true);
        expect(e.message, contains('Could not find an option named'));
      });
    });

    test('--help', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.processArgs(['--help'], directory: foo).then((_) {
        expect(logger.out,
            contains('A tool to improve visibility into your Dart projects.'));
        expect(logger.out, contains('commands:'));
        expect(logger.err, isEmpty);
      });
    });

    test('--version', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.processArgs(['--version'], directory: foo).then((_) {
        expect(logger.out, contains('tuneup version '));
        expect(logger.err, isEmpty);
      });
    });

    test('init', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.processArgs(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      });
    });

    test('stats', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.processArgs(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
        File other = new File('foo/web/index.html');
        other.parent.createSync(recursive: true);
        other.writeAsStringSync('<body>\n  hey!\n</body>\n');
      }).then((_) {
        return tuneup.processArgs(['stats'], directory: foo).then((_) {
          expect(logger.out, contains('2 source files and 6 lines of code'));
          expect(logger.err, isEmpty);
        });
      });
    });

    test('trim', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      File hello = new File('foo/bin/helloworld.dart');
      File other = new File('foo/web/index.html');

      return tuneup.processArgs(['init'], directory: foo).then((_) {
        other.parent.createSync(recursive: true);
        other.writeAsStringSync('<body>\n  hey!\n\n\nfoo \n</body>\n\n\n');
      }).then((_) {
        return tuneup.processArgs(['trim'], directory: foo).then((_) {
          expect(hello.readAsStringSync(),
              "void main() {\n  print('hello world!');\n}\n");
          expect(other.readAsStringSync(), '<body>\n  hey!\n\nfoo\n</body>\n');
        });
      });
    });

    test('check', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.processArgs(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      }).then((_) {
        _setupPub();
        return tuneup.processArgs(['check'], directory: foo);
      }).then((_) {
        expect(
            logger.out, contains('No issues found; analyzed 1 source file in'));
        expect(logger.err, isEmpty);
      });
    });

    test('check with errors', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.processArgs(['init'], directory: foo).then((_) {
        File f = new File('foo/bin/helloworld.dart');
        expect(f.existsSync(), true);
        f.writeAsStringSync(_errorText);
      }).then((_) {
        _setupPub();
        return tuneup.processArgs(['check'], directory: foo);
      }).then((_) {
        fail('expected analysis errors');
      }).catchError((e) {
        expect(e is ExitCode, true);
        expect(
            logger.out, contains('2 issues found; analyzed 1 source file in'));
        expect(logger.err, isEmpty);
      });
    });

    test('clean', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.processArgs(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      }).then((_) {
        new Directory('foo/build').createSync();
        return tuneup.processArgs(['clean'], directory: foo);
      }).then((_) {
        expect(logger.out, contains('Deleting build'));
        expect(logger.err, isEmpty);
      });
    });
  });
}

void _setupPub() {
  File pubspec = new File('foo/pubspec.yaml');
  pubspec.writeAsStringSync('name: foo\n');
  Process.runSync('pub', ['get'], workingDirectory: 'foo');
}

class _Logger implements Logger {
  StringBuffer _out = new StringBuffer();
  StringBuffer _err = new StringBuffer();
  StringBuffer _trc = new StringBuffer();

  void stdout(String message) => _out.writeln(message);
  void stderr(String message) => _err.writeln(message);
  void trace(String message) => _trc.writeln(message);

  Progress progress(String message) => new SimpleProgress(this, message);
  void progressFinished(Progress progress) { }

  void flush() { }

  String get out => _out.toString();
  String get err => _err.toString();
  String get trc => _trc.toString();
}

String _errorText = '''
void main() {
  prints('hello world!')
}
''';
