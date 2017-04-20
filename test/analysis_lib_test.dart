// Copyright (c) 2017, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:tuneup/src/analysis_server_lib.dart';
import 'package:unittest/unittest.dart';

void main() => defineTests();

void defineTests() {
  group('analysis server', () {
    test('responds to version', () async {
      Process process;

      try {
        String sdk = path.dirname(path.dirname(Platform.resolvedExecutable));
        String snapshot = '${sdk}/bin/snapshots/analysis_server.dart.snapshot';

        process = await Process.start('dart', [snapshot, '--sdk', sdk]);
        Stream<String> inStream = process.stdout
            .transform(UTF8.decoder)
            .transform(const LineSplitter());

        Server client = new Server(inStream, (String message) {
          process.stdin.writeln(message);
        });
        await client.server.onConnected.first;

        VersionResult result = await client.server.getVersion();
        expect(result.version, isNotEmpty);
        expect(result.version, startsWith('1.'));
      } finally {
        process?.kill();
      }
    });
  });
}
