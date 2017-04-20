library analysis_tester;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:tuneup/src/analysis_server_lib.dart';

Future main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(print);

  String sdk = path.dirname(path.dirname(Platform.resolvedExecutable));
  String snapshot = '${sdk}/bin/snapshots/analysis_server.dart.snapshot';

  print('Using analysis server at ${snapshot}.');
  print('');

  Process process = await Process.start('dart', [snapshot, '--sdk', sdk]);
  process.exitCode.then((code) => print('analysis server exited: ${code}'));

  Stream<String> inStream =
      process.stdout.transform(UTF8.decoder).transform(const LineSplitter());

  Server client = new Server(inStream, (String message) {
    print('[--> ${message}]');
    process.stdin.writeln(message);
  });

  client.server.onConnected.listen((event) {
    print('server connected: ${event}');
  });

  client.server.onError.listen((ServerError e) {
    print('server error: ${e.message}');
    print(e.stackTrace);
  });

  client.server.getVersion().then((VersionResult result) {
    print('version: ${result}, ${result.version}');
  });

  client.server.setSubscriptions(['STATUS']);
  client.server.onStatus.listen((ServerStatus status) {
    if (status.analysis == null) return;

    print('analysis status: ${status.analysis}');

    if (!status.analysis.isAnalyzing) {
      client.server.shutdown();
    }
  });

  client.analysis.setAnalysisRoots([Directory.current.path], []);
}
