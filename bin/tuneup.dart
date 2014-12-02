// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library tuneup.main;

import 'dart:io';

import 'package:tuneup/tuneup.dart';
import 'package:tuneup/src/common.dart';

void main(List args) {
  Tuneup tuneup = new Tuneup();
  tuneup.processArgs(args).catchError((e, st) {
    if (e is ArgError) {
      // These errors are expected.
      exit(1);
    } else if (e is ExitCode) {
      exit(e.code);
    } else {
      print('${e}');
      if (e is! String) {
        print('${st}');
      }
      exit(1);
    }
  });
}
