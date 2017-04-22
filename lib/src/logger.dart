// Copyright (c) 2017, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' as io;

import 'ansi.dart';

abstract class Logger {
  void stderr(String message);
  void stdout(String message);
  void trace(String message);

  Progress progress(String message);
  void progressFinished(Progress progress);

  void flush();
}

abstract class Progress {
  final String message;

  Progress(this.message);

  void finish();
  void cancel();
}

class StandardLogger implements Logger {
  final Ansi ansi;

  StandardLogger(this.ansi);

  Progress _currentProgress;

  void stderr(String message) {
    io.stderr.writeln(message);
    _currentProgress?.cancel();
    _currentProgress = null;
  }

  void stdout(String message) {
    print(message);
    _currentProgress?.cancel();
    _currentProgress = null;
  }

  void trace(String message) {}

  Progress progress(String message) {
    _currentProgress?.cancel();
    _currentProgress = null;

    Progress progress = ansi.useAnsi
        ? new AnsiProgress(this, ansi, message)
        : new SimpleProgress(this, message, printWhenFinished: false);
    _currentProgress = progress;
    return progress;
  }

  void progressFinished(Progress progress) {
    if (_currentProgress == progress) {
      _currentProgress = null;
    }
  }

  void flush() {}
}

class SimpleProgress extends Progress {
  final Logger logger;
  final bool printWhenFinished;

  SimpleProgress(this.logger, String message, {this.printWhenFinished: true})
      : super(message) {
    logger.stdout('$message...');
  }

  @override
  void cancel() {
    logger.progressFinished(this);
  }

  @override
  void finish() {
    if (printWhenFinished) logger.stdout('$message finished.');
    logger.progressFinished(this);
  }
}

class AnsiProgress extends Progress {
  static const List<String> kAnimationItems = const ['/', '-', '\\', '|'];

  final Logger logger;
  final Ansi ansi;

  int _index = 0;
  Timer _timer;

  AnsiProgress(this.logger, this.ansi, String message) : super(message) {
    io.stdout.write('${message}...  '.padRight(40));

    _timer = new Timer.periodic(new Duration(milliseconds: 80), (t) {
      _index++;
      _updateDisplay();
    });

    _updateDisplay();
  }

  @override
  void cancel() {
    if (_timer.isActive) {
      _timer.cancel();
      _updateDisplay(cancelled: true);
      logger.progressFinished(this);
    }
  }

  @override
  void finish() {
    if (_timer.isActive) {
      _timer.cancel();
      _updateDisplay(isFinal: true);
      logger.progressFinished(this);
    }
  }

  void _updateDisplay({bool isFinal: false, bool cancelled: false}) {
    String char = kAnimationItems[_index % kAnimationItems.length];
    if (isFinal || cancelled) {
      char = ' ';
    }
    io.stdout.write('${ansi.backspace}${char}');
    if (isFinal || cancelled) {
      io.stdout.writeln();
    }
  }
}

class VerboseLogger implements Logger {
  final Ansi ansi;
  Stopwatch _timer;

  String _previousErr;
  String _previousMsg;

  VerboseLogger(this.ansi) {
    _timer = new Stopwatch()..start();
  }

  void stderr(String message) {
    flush();
    _previousErr = '${ansi.red}$message${ansi.none}';
  }

  void stdout(String message) {
    flush();
    _previousMsg = message;
  }

  void trace(String message) {
    flush();
    _previousMsg = '${ansi.gray}$message${ansi.none}';
  }

  Progress progress(String message) => new SimpleProgress(this, message);

  void progressFinished(Progress progress) {}

  void flush() {
    if (_previousErr != null) {
      io.stderr.writeln('${_createTag()} $_previousErr');
      _previousErr = null;
    } else if (_previousMsg != null) {
      io.stdout.writeln('${_createTag()} $_previousMsg');
      _previousMsg = null;
    }
  }

  String _createTag() {
    int millis = _timer.elapsedMilliseconds;
    _timer.reset();
    return '[${millis.toString().padLeft(4)} ms]';
  }
}
