// Copyright (c) 2017, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:tuneup/src/analysis_server_lib.dart';

Future main(List<String> args) async {
  if (args.contains('--mini')) {
    _miniTest();
    return;
  }

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(print);

  Server client = await Server.createFromDefaults(onRead: (String message) {
    print('[<-- $message]');
  }, onWrite: (String message) {
    print('[--> $message]');
  });
  client.processCompleter.future
      .then((int code) => print('analysis server exited: ${code}'));

  dynamic event = await client.server.onConnected.first;
  print('server connected: ${event}');

  client.server.onError.listen((ServerError e) {
    print('server error: ${e.message}');
    print(e.stackTrace);
  });

  VersionResult version = await client.server.getVersion();
  print('version: ${version.version}');

  client.server.setSubscriptions(['STATUS']);
  client.server.onStatus.listen((ServerStatus status) {
    if (status.analysis == null) return;

    print('analysis status: ${status.analysis}');

    if (!status.analysis.isAnalyzing) {
      client.server.shutdown();
    }
  });

  client.analysis.onErrors.listen((AnalysisErrors errors) {
    if (errors.errors.isNotEmpty) {
      print('${errors.errors.length} errors for ${errors.file}');
    }
  });
  client.analysis.setAnalysisRoots([Directory.current.path], []);
}

Future _miniTest() async {
  Server client = await Server.createFromDefaults(
    onRead: print,
    onWrite: print,
  );

  await client.server.onConnected.first;

  VersionResult result = await client.server.getVersion();
  print('version: ${result.version}');

  await client.server.shutdown();
}
