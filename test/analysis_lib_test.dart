// Copyright (c) 2017, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'package:tuneup/src/analysis_server_lib.dart';
import 'package:unittest/unittest.dart';

void main() => defineTests();

void defineTests() {
  group('analysis server', () {
    test('responds to version', () async {
      Server client;

      try {
        client = await Server.createFromDefaults();
        await client.server.onConnected.first;

        VersionResult result = await client.server.getVersion();
        expect(result.version, isNotEmpty);
        expect(result.version, startsWith('1.'));
      } finally {
        client?.dispose();
      }
    });
  });
}
