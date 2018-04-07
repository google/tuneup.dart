// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:test/test.dart';
import 'package:tuneup/src/common.dart';
import 'package:tuneup/tuneup.dart';

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
      return tuneup.run(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      }).then((_) {
        _setupPub();
        return tuneup.run(['check'], directory: foo);
      }).then((_) {
        expect(logger.out,
            contains('No issues found; analyzed 2 source files in'));
        expect(logger.err, isEmpty);
      });
    });

    test('bad command', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.run(['foo_command'], directory: foo).then((_) {
        fail('expected exception');
      }).catchError((e) {
        expect(e is UsageException, true);
        expect(e.toString(), contains('Could not find a command named'));
      });
    });

    test('bad arg', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.run(['--foo', 'bar'], directory: foo).then((_) {
        fail('should have thrown');
      }).catchError((e) {
        expect(e is UsageException, true);
        expect(e.message, contains('Could not find an option named'));
      });
    });

    test('--help', () async {
      final StringBuffer buf = new StringBuffer();

      printHandler(Zone self, ZoneDelegate parent, Zone zone, String line) {
        buf.writeln(line);
      }

      await runZoned(() async {
        Tuneup tuneup = new Tuneup();
        await tuneup.run(['--help'], directory: foo);
      }, zoneSpecification: new ZoneSpecification(print: printHandler));
      expect(buf.toString(),
          contains('A tool to improve visibility into your Dart projects.'));
    });

    test('--version', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.run(['--version'], directory: foo).then((_) {
        expect(logger.out, contains('tuneup version '));
        expect(logger.err, isEmpty);
      });
    });

    test('init', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.run(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      });
    });

    test('stats', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.run(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
        File other = new File('foo/web/index.html');
        other.parent.createSync(recursive: true);
        other.writeAsStringSync('<body>\n  hey!\n</body>\n');
      }).then((_) {
        return tuneup.run(['stats'], directory: foo).then((_) {
          expect(logger.out, contains('2 source files and 6 lines of code'));
          expect(logger.err, isEmpty);
        });
      });
    });

    test('trim', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      File hello = new File('foo/bin/helloworld.dart');
      File other = new File('foo/web/index.html');

      return tuneup.run(['init'], directory: foo).then((_) {
        other.parent.createSync(recursive: true);
        other.writeAsStringSync('<body>\n  hey!\n\n\nfoo \n</body>\n\n\n');
      }).then((_) {
        return tuneup.run(['trim'], directory: foo).then((_) {
          expect(hello.readAsStringSync(),
              "void main() {\n  print('hello world!');\n}\n");
          expect(other.readAsStringSync(), '<body>\n  hey!\n\nfoo\n</body>\n');
        });
      });
    });

    test('check', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.run(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      }).then((_) {
        _setupPub();
        return tuneup.run(['check'], directory: foo);
      }).then((_) {
        expect(logger.out,
            contains('No issues found; analyzed 2 source files in'));
        expect(logger.err, isEmpty);
      });
    });

    test('check with errors', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.run(['init'], directory: foo).then((_) {
        File f = new File('foo/bin/helloworld.dart');
        expect(f.existsSync(), true);
        f.writeAsStringSync(_errorText);
      }).then((_) {
        _setupPub();
        return tuneup.run(['check'], directory: foo);
      }).then((_) {
        fail('expected analysis errors');
      }).catchError((e) {
        expect(e is ExitCode, true);
        expect(
            logger.out, contains('2 issues found; analyzed 2 source files in'));
        expect(logger.err, isEmpty);
      });
    });

    test('clean', () {
      Tuneup tuneup = new Tuneup(logger: logger);
      return tuneup.run(['init'], directory: foo).then((_) {
        expect(new File('foo/bin/helloworld.dart').existsSync(), true);
      }).then((_) {
        new Directory('foo/build').createSync();
        return tuneup.run(['clean'], directory: foo);
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
  Ansi ansi;

  _Logger() {
    ansi = new Ansi(false);
  }

  StringBuffer _out = new StringBuffer();
  StringBuffer _err = new StringBuffer();
  StringBuffer _trc = new StringBuffer();

  void stdout(String message) => _out.writeln(message);
  void stderr(String message) => _err.writeln(message);
  void trace(String message) => _trc.writeln(message);

  Progress progress(String message) => new _Progress(message);
  void progressFinished(Progress progress) {}

  void flush() {}

  String get out => _out.toString();
  String get err => _err.toString();
  String get trc => _trc.toString();

  bool get isVerbose => true;
}

String _errorText = '''
void main() {
  prints('hello world!')
}
''';

class _Progress implements Progress {
  final String message;
  Stopwatch timer;

  _Progress(this.message) {
    timer = new Stopwatch()..start();
  }
  @override
  void cancel() {}

  @override
  Duration get elapsed => timer.elapsed;

  @override
  void finish({String message, bool showTiming}) {}
}
