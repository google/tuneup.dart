// Copyright (c) 2017, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// This is a generated file.

/// A library to access the analysis server API.
library analysis_server;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// @optional
const String optional = 'optional';

/// @experimental
const String experimental = 'experimental';

final Logger _logger = new Logger('analysis_server');

const String generatedProtocolVersion = '1.18.1';

typedef void MethodSend(String methodName);

/// A class to communicate with an analysis server instance.
class AnalysisServer {
  /// Create and connect to a new analysis server instance.
  ///
  /// - [sdkPath] override the default sdk path
  /// - [scriptPath] override the default entry-point script to use for the
  ///     analysis server
  /// - [onRead] called every time data is read from the server
  /// - [onWrite] called every time data is written to the server
  static Future<AnalysisServer> create({
    String sdkPath,
    String scriptPath,
    onRead(String),
    onWrite(String),
    List<String> vmArgs,
    List<String> serverArgs,
  }) async {
    Completer<int> processCompleter = new Completer();

    sdkPath ??= path.dirname(path.dirname(Platform.resolvedExecutable));
    scriptPath ??= '$sdkPath/bin/snapshots/analysis_server.dart.snapshot';

    List<String> args = [scriptPath, '--sdk', sdkPath];
    if (vmArgs != null) args.insertAll(0, vmArgs);
    if (serverArgs != null) args.addAll(serverArgs);
    Process process = await Process.start(Platform.resolvedExecutable, args);
    process.exitCode.then((code) => processCompleter.complete(code));

    Stream<String> inStream = process.stdout
        .transform(UTF8.decoder)
        .transform(const LineSplitter())
        .map((String message) {
      if (onRead != null) onRead(message);
      return message;
    });

    AnalysisServer server = new AnalysisServer(inStream, (String message) {
      if (onWrite != null) onWrite(message);
      process.stdin.writeln(message);
    }, processCompleter, process.kill);

    return server;
  }

  final Completer<int> processCompleter;
  final Function _processKillHandler;

  StreamSubscription _streamSub;
  Function _writeMessage;
  int _id = 0;
  Map<String, Completer> _completers = {};
  Map<String, String> _methodNames = {};
  JsonCodec _jsonEncoder = new JsonCodec(toEncodable: _toEncodable);
  Map<String, Domain> _domains = {};
  StreamController<String> _onSend = new StreamController.broadcast();
  StreamController<String> _onReceive = new StreamController.broadcast();
  MethodSend _willSend;

  ServerDomain _server;
  AnalysisDomain _analysis;
  CompletionDomain _completion;
  SearchDomain _search;
  EditDomain _edit;
  ExecutionDomain _execution;
  DiagnosticDomain _diagnostic;

  /// Connect to an existing analysis server instance.
  AnalysisServer(Stream<String> inStream, void writeMessage(String message),
      this.processCompleter,
      [this._processKillHandler]) {
    configure(inStream, writeMessage);

    _server = new ServerDomain(this);
    _analysis = new AnalysisDomain(this);
    _completion = new CompletionDomain(this);
    _search = new SearchDomain(this);
    _edit = new EditDomain(this);
    _execution = new ExecutionDomain(this);
    _diagnostic = new DiagnosticDomain(this);
  }

  ServerDomain get server => _server;
  AnalysisDomain get analysis => _analysis;
  CompletionDomain get completion => _completion;
  SearchDomain get search => _search;
  EditDomain get edit => _edit;
  ExecutionDomain get execution => _execution;
  DiagnosticDomain get diagnostic => _diagnostic;

  Stream<String> get onSend => _onSend.stream;
  Stream<String> get onReceive => _onReceive.stream;

  set willSend(MethodSend fn) {
    _willSend = fn;
  }

  void configure(Stream<String> inStream, void writeMessage(String message)) {
    _streamSub = inStream.listen(_processMessage);
    _writeMessage = writeMessage;
  }

  void dispose() {
    if (_streamSub != null) _streamSub.cancel();
    //_completers.values.forEach((c) => c.completeError('disposed'));
    _completers.clear();

    if (_processKillHandler != null) {
      _processKillHandler();
    }
  }

  void _processMessage(String message) {
    _onReceive.add(message);

    if (!message.startsWith('{')) {
      _logger.warning('unknown message: ${message}');
      return;
    }

    try {
      var json = JSON.decode(message);

      if (json['id'] == null) {
        // Handle a notification.
        String event = json['event'];
        if (event == null) {
          _logger.severe('invalid message: ${message}');
        } else {
          String prefix = event.substring(0, event.indexOf('.'));
          if (_domains[prefix] == null) {
            _logger.severe('no domain for notification: ${message}');
          } else {
            _domains[prefix]._handleEvent(event, json['params']);
          }
        }
      } else {
        Completer completer = _completers.remove(json['id']);
        String methodName = _methodNames.remove(json['id']);

        if (completer == null) {
          _logger.severe('unmatched request response: ${message}');
        } else if (json['error'] != null) {
          completer
              .completeError(RequestError.parse(methodName, json['error']));
        } else {
          completer.complete(json['result']);
        }
      }
    } catch (e) {
      _logger.severe('unable to decode message: ${message}, ${e}');
    }
  }

  Future _call(String method, [Map args]) {
    String id = '${++_id}';
    _completers[id] = new Completer();
    _methodNames[id] = method;
    Map m = {'id': id, 'method': method};
    if (args != null) m['params'] = args;
    String message = _jsonEncoder.encode(m);
    if (_willSend != null) _willSend(method);
    _onSend.add(message);
    _writeMessage(message);
    return _completers[id].future;
  }

  static dynamic _toEncodable(obj) => obj is Jsonable ? obj.toMap() : obj;
}

abstract class Domain {
  final AnalysisServer server;
  final String name;

  Map<String, StreamController> _controllers = {};
  Map<String, Stream> _streams = {};

  Domain(this.server, this.name) {
    server._domains[name] = this;
  }

  Future _call(String method, [Map args]) => server._call(method, args);

  Stream<dynamic> _listen(String name, Function cvt) {
    if (_streams[name] == null) {
      _controllers[name] = new StreamController.broadcast();
      _streams[name] = _controllers[name].stream.map(cvt);
    }

    return _streams[name];
  }

  void _handleEvent(String name, dynamic event) {
    if (_controllers[name] != null) {
      _controllers[name].add(event);
    }
  }

  String toString() => 'Domain ${name}';
}

abstract class Jsonable {
  Map toMap();
}

abstract class RefactoringOptions implements Jsonable {}

abstract class ContentOverlayType {
  final String type;

  ContentOverlayType(this.type);
}

class RequestError {
  static RequestError parse(String method, Map m) {
    if (m == null) return null;
    return new RequestError(method, m['code'], m['message'],
        stackTrace: m['stackTrace']);
  }

  final String method;
  final String code;
  final String message;
  @optional
  final String stackTrace;

  RequestError(this.method, this.code, this.message, {this.stackTrace});

  String toString() =>
      '[Analyzer RequestError method: ${method}, code: ${code}, message: ${message}]';
}

Map _stripNullValues(Map m) {
  Map copy = {};

  for (var key in m.keys) {
    var value = m[key];
    if (value != null) copy[key] = value;
  }

  return copy;
}

// server domain

/// The server domain contains API’s related to the execution of the server.
class ServerDomain extends Domain {
  ServerDomain(AnalysisServer server) : super(server, 'server');

  /// Reports that the server is running. This notification is issued once after
  /// the server has started running but before any requests are processed to
  /// let the client know that it started correctly.
  ///
  /// It is not possible to subscribe to or unsubscribe from this notification.
  Stream<ServerConnected> get onConnected {
    return _listen('server.connected', ServerConnected.parse);
  }

  /// Reports that an unexpected error has occurred while executing the server.
  /// This notification is not used for problems with specific requests (which
  /// are returned as part of the response) but is used for exceptions that
  /// occur while performing other tasks, such as analysis or preparing
  /// notifications.
  ///
  /// It is not possible to subscribe to or unsubscribe from this notification.
  Stream<ServerError> get onError {
    return _listen('server.error', ServerError.parse);
  }

  /// Reports the current status of the server. Parameters are omitted if there
  /// has been no change in the status represented by that parameter.
  ///
  /// This notification is not subscribed to by default. Clients can subscribe
  /// by including the value `"STATUS"` in the list of services passed in a
  /// server.setSubscriptions request.
  Stream<ServerStatus> get onStatus {
    return _listen('server.status', ServerStatus.parse);
  }

  /// Return the version number of the analysis server.
  Future<VersionResult> getVersion() =>
      _call('server.getVersion').then(VersionResult.parse);

  /// Cleanly shutdown the analysis server. Requests that are received after
  /// this request will not be processed. Requests that were received before
  /// this request, but for which a response has not yet been sent, will not be
  /// responded to. No further responses or notifications will be sent after the
  /// response to this request has been sent.
  Future shutdown() => _call('server.shutdown');

  /// Subscribe for services. All previous subscriptions are replaced by the
  /// given set of services.
  ///
  /// It is an error if any of the elements in the list are not valid services.
  /// If there is an error, then the current subscriptions will remain
  /// unchanged.
  Future setSubscriptions(List<String> subscriptions) =>
      _call('server.setSubscriptions', {'subscriptions': subscriptions});
}

class ServerConnected {
  static ServerConnected parse(Map m) =>
      new ServerConnected(m['version'], m['pid'], sessionId: m['sessionId']);

  /// The version number of the analysis server.
  final String version;

  /// The process id of the analysis server process.
  final int pid;

  /// The session id for this session.
  @optional
  final String sessionId;

  ServerConnected(this.version, this.pid, {this.sessionId});
}

class ServerError {
  static ServerError parse(Map m) =>
      new ServerError(m['isFatal'], m['message'], m['stackTrace']);

  /// True if the error is a fatal error, meaning that the server will shutdown
  /// automatically after sending this notification.
  final bool isFatal;

  /// The error message indicating what kind of error was encountered.
  final String message;

  /// The stack trace associated with the generation of the error, used for
  /// debugging the server.
  final String stackTrace;

  ServerError(this.isFatal, this.message, this.stackTrace);
}

class ServerStatus {
  static ServerStatus parse(Map m) => new ServerStatus(
      analysis: AnalysisStatus.parse(m['analysis']),
      pub: PubStatus.parse(m['pub']));

  /// The current status of analysis, including whether analysis is being
  /// performed and if so what is being analyzed.
  @optional
  final AnalysisStatus analysis;

  /// The current status of pub execution, indicating whether we are currently
  /// running pub.
  @optional
  final PubStatus pub;

  ServerStatus({this.analysis, this.pub});
}

class VersionResult {
  static VersionResult parse(Map m) => new VersionResult(m['version']);

  /// The version number of the analysis server.
  final String version;

  VersionResult(this.version);
}

// analysis domain

/// The analysis domain contains API’s related to the analysis of files.
class AnalysisDomain extends Domain {
  AnalysisDomain(AnalysisServer server) : super(server, 'analysis');

  /// Reports the paths of the files that are being analyzed.
  ///
  /// This notification is not subscribed to by default. Clients can subscribe
  /// by including the value `"ANALYZED_FILES"` in the list of services passed
  /// in an analysis.setGeneralSubscriptions request.
  Stream<AnalysisAnalyzedFiles> get onAnalyzedFiles {
    return _listen('analysis.analyzedFiles', AnalysisAnalyzedFiles.parse);
  }

  /// Reports the errors associated with a given file. The set of errors
  /// included in the notification is always a complete list that supersedes any
  /// previously reported errors.
  Stream<AnalysisErrors> get onErrors {
    return _listen('analysis.errors', AnalysisErrors.parse);
  }

  /// Reports that any analysis results that were previously associated with the
  /// given files should be considered to be invalid because those files are no
  /// longer being analyzed, either because the analysis root that contained it
  /// is no longer being analyzed or because the file no longer exists.
  ///
  /// If a file is included in this notification and at some later time a
  /// notification with results for the file is received, clients should assume
  /// that the file is once again being analyzed and the information should be
  /// processed.
  ///
  /// It is not possible to subscribe to or unsubscribe from this notification.
  Stream<AnalysisFlushResults> get onFlushResults {
    return _listen('analysis.flushResults', AnalysisFlushResults.parse);
  }

  /// Reports the folding regions associated with a given file. Folding regions
  /// can be nested, but will not be overlapping. Nesting occurs when a foldable
  /// element, such as a method, is nested inside another foldable element such
  /// as a class.
  ///
  /// This notification is not subscribed to by default. Clients can subscribe
  /// by including the value `"FOLDING"` in the list of services passed in an
  /// analysis.setSubscriptions request.
  Stream<AnalysisFolding> get onFolding {
    return _listen('analysis.folding', AnalysisFolding.parse);
  }

  /// Reports the highlight regions associated with a given file.
  ///
  /// This notification is not subscribed to by default. Clients can subscribe
  /// by including the value `"HIGHLIGHTS"` in the list of services passed in an
  /// analysis.setSubscriptions request.
  Stream<AnalysisHighlights> get onHighlights {
    return _listen('analysis.highlights', AnalysisHighlights.parse);
  }

  /// Reports the classes that are implemented or extended and class members
  /// that are implemented or overridden in a file.
  ///
  /// This notification is not subscribed to by default. Clients can subscribe
  /// by including the value `"IMPLEMENTED"` in the list of services passed in
  /// an analysis.setSubscriptions request.
  Stream<AnalysisImplemented> get onImplemented {
    return _listen('analysis.implemented', AnalysisImplemented.parse);
  }

  /// Reports that the navigation information associated with a region of a
  /// single file has become invalid and should be re-requested.
  ///
  /// This notification is not subscribed to by default. Clients can subscribe
  /// by including the value `"INVALIDATE"` in the list of services passed in an
  /// analysis.setSubscriptions request.
  Stream<AnalysisInvalidate> get onInvalidate {
    return _listen('analysis.invalidate', AnalysisInvalidate.parse);
  }

  /// Reports the navigation targets associated with a given file.
  ///
  /// This notification is not subscribed to by default. Clients can subscribe
  /// by including the value `"NAVIGATION"` in the list of services passed in an
  /// analysis.setSubscriptions request.
  Stream<AnalysisNavigation> get onNavigation {
    return _listen('analysis.navigation', AnalysisNavigation.parse);
  }

  /// Reports the occurrences of references to elements within a single file.
  ///
  /// This notification is not subscribed to by default. Clients can subscribe
  /// by including the value `"OCCURRENCES"` in the list of services passed in
  /// an analysis.setSubscriptions request.
  Stream<AnalysisOccurrences> get onOccurrences {
    return _listen('analysis.occurrences', AnalysisOccurrences.parse);
  }

  /// Reports the outline associated with a single file.
  ///
  /// This notification is not subscribed to by default. Clients can subscribe
  /// by including the value `"OUTLINE"` in the list of services passed in an
  /// analysis.setSubscriptions request.
  Stream<AnalysisOutline> get onOutline {
    return _listen('analysis.outline', AnalysisOutline.parse);
  }

  /// Reports the overriding members in a file.
  ///
  /// This notification is not subscribed to by default. Clients can subscribe
  /// by including the value `"OVERRIDES"` in the list of services passed in an
  /// analysis.setSubscriptions request.
  Stream<AnalysisOverrides> get onOverrides {
    return _listen('analysis.overrides', AnalysisOverrides.parse);
  }

  /// Return the errors associated with the given file. If the errors for the
  /// given file have not yet been computed, or the most recently computed
  /// errors for the given file are out of date, then the response for this
  /// request will be delayed until they have been computed. If some or all of
  /// the errors for the file cannot be computed, then the subset of the errors
  /// that can be computed will be returned and the response will contain an
  /// error to indicate why the errors could not be computed. If the content of
  /// the file changes after this request was received but before a response
  /// could be sent, then an error of type `CONTENT_MODIFIED` will be generated.
  ///
  /// This request is intended to be used by clients that cannot asynchronously
  /// apply updated error information. Clients that **can** apply error
  /// information as it becomes available should use the information provided by
  /// the 'analysis.errors' notification.
  ///
  /// If a request is made for a file which does not exist, or which is not
  /// currently subject to analysis (e.g. because it is not associated with any
  /// analysis root specified to analysis.setAnalysisRoots), an error of type
  /// `GET_ERRORS_INVALID_FILE` will be generated.
  Future<ErrorsResult> getErrors(String file) {
    Map m = {'file': file};
    return _call('analysis.getErrors', m).then(ErrorsResult.parse);
  }

  /// Return the hover information associate with the given location. If some or
  /// all of the hover information is not available at the time this request is
  /// processed the information will be omitted from the response.
  Future<HoverResult> getHover(String file, int offset) {
    Map m = {'file': file, 'offset': offset};
    return _call('analysis.getHover', m).then(HoverResult.parse);
  }

  /// Return the transitive closure of reachable sources for a given file.
  ///
  /// If a request is made for a file which does not exist, or which is not
  /// currently subject to analysis (e.g. because it is not associated with any
  /// analysis root specified to analysis.setAnalysisRoots), an error of type
  /// `GET_REACHABLE_SOURCES_INVALID_FILE` will be generated.
  Future<ReachableSourcesResult> getReachableSources(String file) {
    Map m = {'file': file};
    return _call('analysis.getReachableSources', m)
        .then(ReachableSourcesResult.parse);
  }

  /// Return library dependency information for use in client-side indexing and
  /// package URI resolution.
  ///
  /// Clients that are only using the libraries field should consider using the
  /// analyzedFiles notification instead.
  Future<LibraryDependenciesResult> getLibraryDependencies() =>
      _call('analysis.getLibraryDependencies')
          .then(LibraryDependenciesResult.parse);

  /// Return the navigation information associated with the given region of the
  /// given file. If the navigation information for the given file has not yet
  /// been computed, or the most recently computed navigation information for
  /// the given file is out of date, then the response for this request will be
  /// delayed until it has been computed. If the content of the file changes
  /// after this request was received but before a response could be sent, then
  /// an error of type `CONTENT_MODIFIED` will be generated.
  ///
  /// If a navigation region overlaps (but extends either before or after) the
  /// given region of the file it will be included in the result. This means
  /// that it is theoretically possible to get the same navigation region in
  /// response to multiple requests. Clients can avoid this by always choosing a
  /// region that starts at the beginning of a line and ends at the end of a
  /// (possibly different) line in the file.
  ///
  /// If a request is made for a file which does not exist, or which is not
  /// currently subject to analysis (e.g. because it is not associated with any
  /// analysis root specified to analysis.setAnalysisRoots), an error of type
  /// `GET_NAVIGATION_INVALID_FILE` will be generated.
  Future<NavigationResult> getNavigation(String file, int offset, int length) {
    Map m = {'file': file, 'offset': offset, 'length': length};
    return _call('analysis.getNavigation', m).then(NavigationResult.parse);
  }

  /// Force the re-analysis of everything contained in the specified analysis
  /// roots. This will cause all previously computed analysis results to be
  /// discarded and recomputed, and will cause all subscribed notifications to
  /// be re-sent.
  ///
  /// If no analysis roots are provided, then all current analysis roots will be
  /// re-analyzed. If an empty list of analysis roots is provided, then nothing
  /// will be re-analyzed. If the list contains one or more paths that are not
  /// currently analysis roots, then an error of type `INVALID_ANALYSIS_ROOT`
  /// will be generated.
  Future reanalyze({List<String> roots}) {
    Map m = {};
    if (roots != null) m['roots'] = roots;
    return _call('analysis.reanalyze', m);
  }

  /// Sets the root paths used to determine which files to analyze. The set of
  /// files to be analyzed are all of the files in one of the root paths that
  /// are not either explicitly or implicitly excluded. A file is explicitly
  /// excluded if it is in one of the excluded paths. A file is implicitly
  /// excluded if it is in a subdirectory of one of the root paths where the
  /// name of the subdirectory starts with a period (that is, a hidden
  /// directory).
  ///
  /// Note that this request determines the set of requested analysis roots. The
  /// actual set of analysis roots at any given time is the intersection of this
  /// set with the set of files and directories actually present on the
  /// filesystem. When the filesystem changes, the actual set of analysis roots
  /// is automatically updated, but the set of requested analysis roots is
  /// unchanged. This means that if the client sets an analysis root before the
  /// root becomes visible to server in the filesystem, there is no error; once
  /// the server sees the root in the filesystem it will start analyzing it.
  /// Similarly, server will stop analyzing files that are removed from the file
  /// system but they will remain in the set of requested roots.
  ///
  /// If an included path represents a file, then server will look in the
  /// directory containing the file for a pubspec.yaml file. If none is found,
  /// then the parents of the directory will be searched until such a file is
  /// found or the root of the file system is reached. If such a file is found,
  /// it will be used to resolve package: URI’s within the file.
  Future setAnalysisRoots(List<String> included, List<String> excluded,
      {Map<String, String> packageRoots}) {
    Map m = {'included': included, 'excluded': excluded};
    if (packageRoots != null) m['packageRoots'] = packageRoots;
    return _call('analysis.setAnalysisRoots', m);
  }

  /// Subscribe for general services (that is, services that are not specific to
  /// individual files). All previous subscriptions are replaced by the given
  /// set of services.
  ///
  /// It is an error if any of the elements in the list are not valid services.
  /// If there is an error, then the current subscriptions will remain
  /// unchanged.
  Future setGeneralSubscriptions(List<String> subscriptions) => _call(
      'analysis.setGeneralSubscriptions', {'subscriptions': subscriptions});

  /// Set the priority files to the files in the given list. A priority file is
  /// a file that is given priority when scheduling which analysis work to do
  /// first. The list typically contains those files that are visible to the
  /// user and those for which analysis results will have the biggest impact on
  /// the user experience. The order of the files within the list is
  /// significant: the first file will be given higher priority than the second,
  /// the second higher priority than the third, and so on.
  ///
  /// Note that this request determines the set of requested priority files. The
  /// actual set of priority files is the intersection of the requested set of
  /// priority files with the set of files currently subject to analysis. (See
  /// analysis.setSubscriptions for a description of files that are subject to
  /// analysis.)
  ///
  /// If a requested priority file is a directory it is ignored, but remains in
  /// the set of requested priority files so that if it later becomes a file it
  /// can be included in the set of actual priority files.
  Future setPriorityFiles(List<String> files) =>
      _call('analysis.setPriorityFiles', {'files': files});

  /// Subscribe for services that are specific to individual files. All previous
  /// subscriptions are replaced by the current set of subscriptions. If a given
  /// service is not included as a key in the map then no files will be
  /// subscribed to the service, exactly as if the service had been included in
  /// the map with an explicit empty list of files.
  ///
  /// Note that this request determines the set of requested subscriptions. The
  /// actual set of subscriptions at any given time is the intersection of this
  /// set with the set of files currently subject to analysis. The files
  /// currently subject to analysis are the set of files contained within an
  /// actual analysis root but not excluded, plus all of the files transitively
  /// reachable from those files via import, export and part directives. (See
  /// analysis.setAnalysisRoots for an explanation of how the actual analysis
  /// roots are determined.) When the actual analysis roots change, the actual
  /// set of subscriptions is automatically updated, but the set of requested
  /// subscriptions is unchanged.
  ///
  /// If a requested subscription is a directory it is ignored, but remains in
  /// the set of requested subscriptions so that if it later becomes a file it
  /// can be included in the set of actual subscriptions.
  ///
  /// It is an error if any of the keys in the map are not valid services. If
  /// there is an error, then the existing subscriptions will remain unchanged.
  Future setSubscriptions(Map<String, List<String>> subscriptions) =>
      _call('analysis.setSubscriptions', {'subscriptions': subscriptions});

  /// Update the content of one or more files. Files that were previously
  /// updated but not included in this update remain unchanged. This effectively
  /// represents an overlay of the filesystem. The files whose content is
  /// overridden are therefore seen by server as being files with the given
  /// content, even if the files do not exist on the filesystem or if the file
  /// path represents the path to a directory on the filesystem.
  Future updateContent(Map<String, ContentOverlayType> files) =>
      _call('analysis.updateContent', {'files': files});

  @deprecated
  Future updateOptions(AnalysisOptions options) =>
      _call('analysis.updateOptions', {'options': options});
}

class AnalysisAnalyzedFiles {
  static AnalysisAnalyzedFiles parse(Map m) => new AnalysisAnalyzedFiles(
      m['directories'] == null ? null : new List.from(m['directories']));

  /// A list of the paths of the files that are being analyzed.
  final List<String> directories;

  AnalysisAnalyzedFiles(this.directories);
}

class AnalysisErrors {
  static AnalysisErrors parse(Map m) => new AnalysisErrors(
      m['file'],
      m['errors'] == null
          ? null
          : new List.from(m['errors'].map((obj) => AnalysisError.parse(obj))));

  /// The file containing the errors.
  final String file;

  /// The errors contained in the file.
  final List<AnalysisError> errors;

  AnalysisErrors(this.file, this.errors);
}

class AnalysisFlushResults {
  static AnalysisFlushResults parse(Map m) => new AnalysisFlushResults(
      m['files'] == null ? null : new List.from(m['files']));

  /// The files that are no longer being analyzed.
  final List<String> files;

  AnalysisFlushResults(this.files);
}

class AnalysisFolding {
  static AnalysisFolding parse(Map m) => new AnalysisFolding(
      m['file'],
      m['regions'] == null
          ? null
          : new List.from(m['regions'].map((obj) => FoldingRegion.parse(obj))));

  /// The file containing the folding regions.
  final String file;

  /// The folding regions contained in the file.
  final List<FoldingRegion> regions;

  AnalysisFolding(this.file, this.regions);
}

class AnalysisHighlights {
  static AnalysisHighlights parse(Map m) => new AnalysisHighlights(
      m['file'],
      m['regions'] == null
          ? null
          : new List.from(
              m['regions'].map((obj) => HighlightRegion.parse(obj))));

  /// The file containing the highlight regions.
  final String file;

  /// The highlight regions contained in the file. Each highlight region
  /// represents a particular syntactic or semantic meaning associated with some
  /// range. Note that the highlight regions that are returned can overlap other
  /// highlight regions if there is more than one meaning associated with a
  /// particular region.
  final List<HighlightRegion> regions;

  AnalysisHighlights(this.file, this.regions);
}

class AnalysisImplemented {
  static AnalysisImplemented parse(Map m) => new AnalysisImplemented(
      m['file'],
      m['classes'] == null
          ? null
          : new List.from(
              m['classes'].map((obj) => ImplementedClass.parse(obj))),
      m['members'] == null
          ? null
          : new List.from(
              m['members'].map((obj) => ImplementedMember.parse(obj))));

  /// The file with which the implementations are associated.
  final String file;

  /// The classes defined in the file that are implemented or extended.
  final List<ImplementedClass> classes;

  /// The member defined in the file that are implemented or overridden.
  final List<ImplementedMember> members;

  AnalysisImplemented(this.file, this.classes, this.members);
}

class AnalysisInvalidate {
  static AnalysisInvalidate parse(Map m) =>
      new AnalysisInvalidate(m['file'], m['offset'], m['length'], m['delta']);

  /// The file whose information has been invalidated.
  final String file;

  /// The offset of the invalidated region.
  final int offset;

  /// The length of the invalidated region.
  final int length;

  /// The delta to be applied to the offsets in information that follows the
  /// invalidated region in order to update it so that it doesn't need to be
  /// re-requested.
  final int delta;

  AnalysisInvalidate(this.file, this.offset, this.length, this.delta);
}

class AnalysisNavigation {
  static AnalysisNavigation parse(Map m) => new AnalysisNavigation(
      m['file'],
      m['regions'] == null
          ? null
          : new List.from(
              m['regions'].map((obj) => NavigationRegion.parse(obj))),
      m['targets'] == null
          ? null
          : new List.from(
              m['targets'].map((obj) => NavigationTarget.parse(obj))),
      m['files'] == null ? null : new List.from(m['files']));

  /// The file containing the navigation regions.
  final String file;

  /// The navigation regions contained in the file. The regions are sorted by
  /// their offsets. Each navigation region represents a list of targets
  /// associated with some range. The lists will usually contain a single
  /// target, but can contain more in the case of a part that is included in
  /// multiple libraries or in Dart code that is compiled against multiple
  /// versions of a package. Note that the navigation regions that are returned
  /// do not overlap other navigation regions.
  final List<NavigationRegion> regions;

  /// The navigation targets referenced in the file. They are referenced by
  /// `NavigationRegion`s by their index in this array.
  final List<NavigationTarget> targets;

  /// The files containing navigation targets referenced in the file. They are
  /// referenced by `NavigationTarget`s by their index in this array.
  final List<String> files;

  AnalysisNavigation(this.file, this.regions, this.targets, this.files);
}

class AnalysisOccurrences {
  static AnalysisOccurrences parse(Map m) => new AnalysisOccurrences(
      m['file'],
      m['occurrences'] == null
          ? null
          : new List.from(
              m['occurrences'].map((obj) => Occurrences.parse(obj))));

  /// The file in which the references occur.
  final String file;

  /// The occurrences of references to elements within the file.
  final List<Occurrences> occurrences;

  AnalysisOccurrences(this.file, this.occurrences);
}

class AnalysisOutline {
  static AnalysisOutline parse(Map m) =>
      new AnalysisOutline(m['file'], m['kind'], Outline.parse(m['outline']),
          libraryName: m['libraryName']);

  /// The file with which the outline is associated.
  final String file;

  /// The kind of the file.
  final String kind;

  /// The outline associated with the file.
  final Outline outline;

  /// The name of the library defined by the file using a "library" directive,
  /// or referenced by a "part of" directive. If both "library" and "part of"
  /// directives are present, then the "library" directive takes precedence.
  /// This field will be omitted if the file has neither "library" nor "part of"
  /// directives.
  @optional
  final String libraryName;

  AnalysisOutline(this.file, this.kind, this.outline, {this.libraryName});
}

class AnalysisOverrides {
  static AnalysisOverrides parse(Map m) => new AnalysisOverrides(
      m['file'],
      m['overrides'] == null
          ? null
          : new List.from(m['overrides'].map((obj) => Override.parse(obj))));

  /// The file with which the overrides are associated.
  final String file;

  /// The overrides associated with the file.
  final List<Override> overrides;

  AnalysisOverrides(this.file, this.overrides);
}

class ErrorsResult {
  static ErrorsResult parse(Map m) => new ErrorsResult(m['errors'] == null
      ? null
      : new List.from(m['errors'].map((obj) => AnalysisError.parse(obj))));

  /// The errors associated with the file.
  final List<AnalysisError> errors;

  ErrorsResult(this.errors);
}

class HoverResult {
  static HoverResult parse(Map m) => new HoverResult(m['hovers'] == null
      ? null
      : new List.from(m['hovers'].map((obj) => HoverInformation.parse(obj))));

  /// The hover information associated with the location. The list will be empty
  /// if no information could be determined for the location. The list can
  /// contain multiple items if the file is being analyzed in multiple contexts
  /// in conflicting ways (such as a part that is included in multiple
  /// libraries).
  final List<HoverInformation> hovers;

  HoverResult(this.hovers);
}

class ReachableSourcesResult {
  static ReachableSourcesResult parse(Map m) =>
      new ReachableSourcesResult(new Map.from(m['sources']));

  /// A mapping from source URIs to directly reachable source URIs. For example,
  /// a file "foo.dart" that imports "bar.dart" would have the corresponding
  /// mapping { "file:///foo.dart" : ["file:///bar.dart"] }. If "bar.dart" has
  /// further imports (or exports) there will be a mapping from the URI
  /// "file:///bar.dart" to them. To check if a specific URI is reachable from a
  /// given file, clients can check for its presence in the resulting key set.
  final Map<String, List<String>> sources;

  ReachableSourcesResult(this.sources);
}

class LibraryDependenciesResult {
  static LibraryDependenciesResult parse(Map m) =>
      new LibraryDependenciesResult(
          m['libraries'] == null ? null : new List.from(m['libraries']),
          new Map.from(m['packageMap']));

  /// A list of the paths of library elements referenced by files in existing
  /// analysis roots.
  final List<String> libraries;

  /// A mapping from context source roots to package maps which map package
  /// names to source directories for use in client-side package URI resolution.
  final Map<String, Map<String, List<String>>> packageMap;

  LibraryDependenciesResult(this.libraries, this.packageMap);
}

class NavigationResult {
  static NavigationResult parse(Map m) => new NavigationResult(
      m['files'] == null ? null : new List.from(m['files']),
      m['targets'] == null
          ? null
          : new List.from(
              m['targets'].map((obj) => NavigationTarget.parse(obj))),
      m['regions'] == null
          ? null
          : new List.from(
              m['regions'].map((obj) => NavigationRegion.parse(obj))));

  /// A list of the paths of files that are referenced by the navigation
  /// targets.
  final List<String> files;

  /// A list of the navigation targets that are referenced by the navigation
  /// regions.
  final List<NavigationTarget> targets;

  /// A list of the navigation regions within the requested region of the file.
  final List<NavigationRegion> regions;

  NavigationResult(this.files, this.targets, this.regions);
}

// completion domain

/// The code completion domain contains commands related to getting code
/// completion suggestions.
class CompletionDomain extends Domain {
  CompletionDomain(AnalysisServer server) : super(server, 'completion');

  /// Reports the completion suggestions that should be presented to the user.
  /// The set of suggestions included in the notification is always a complete
  /// list that supersedes any previously reported suggestions.
  Stream<CompletionResults> get onResults {
    return _listen('completion.results', CompletionResults.parse);
  }

  /// Request that completion suggestions for the given offset in the given file
  /// be returned.
  Future<SuggestionsResult> getSuggestions(String file, int offset) {
    Map m = {'file': file, 'offset': offset};
    return _call('completion.getSuggestions', m).then(SuggestionsResult.parse);
  }
}

class CompletionResults {
  static CompletionResults parse(Map m) => new CompletionResults(
      m['id'],
      m['replacementOffset'],
      m['replacementLength'],
      m['results'] == null
          ? null
          : new List.from(
              m['results'].map((obj) => CompletionSuggestion.parse(obj))),
      m['isLast']);

  /// The id associated with the completion.
  final String id;

  /// The offset of the start of the text to be replaced. This will be different
  /// than the offset used to request the completion suggestions if there was a
  /// portion of an identifier before the original offset. In particular, the
  /// replacementOffset will be the offset of the beginning of said identifier.
  final int replacementOffset;

  /// The length of the text to be replaced if the remainder of the identifier
  /// containing the cursor is to be replaced when the suggestion is applied
  /// (that is, the number of characters in the existing identifier).
  final int replacementLength;

  /// The completion suggestions being reported. The notification contains all
  /// possible completions at the requested cursor position, even those that do
  /// not match the characters the user has already typed. This allows the
  /// client to respond to further keystrokes from the user without having to
  /// make additional requests.
  final List<CompletionSuggestion> results;

  /// True if this is that last set of results that will be returned for the
  /// indicated completion.
  final bool isLast;

  CompletionResults(this.id, this.replacementOffset, this.replacementLength,
      this.results, this.isLast);
}

class SuggestionsResult {
  static SuggestionsResult parse(Map m) => new SuggestionsResult(m['id']);

  /// The identifier used to associate results with this completion request.
  final String id;

  SuggestionsResult(this.id);
}

// search domain

/// The search domain contains commands related to searches that can be
/// performed against the code base.
class SearchDomain extends Domain {
  SearchDomain(AnalysisServer server) : super(server, 'search');

  /// Reports some or all of the results of performing a requested search.
  /// Unlike other notifications, this notification contains search results that
  /// should be added to any previously received search results associated with
  /// the same search id.
  Stream<SearchResults> get onResults {
    return _listen('search.results', SearchResults.parse);
  }

  /// Perform a search for references to the element defined or referenced at
  /// the given offset in the given file.
  ///
  /// An identifier is returned immediately, and individual results will be
  /// returned via the search.results notification as they become available.
  Future<FindElementReferencesResult> findElementReferences(
      String file, int offset, bool includePotential) {
    Map m = {
      'file': file,
      'offset': offset,
      'includePotential': includePotential
    };
    return _call('search.findElementReferences', m)
        .then(FindElementReferencesResult.parse);
  }

  /// Perform a search for declarations of members whose name is equal to the
  /// given name.
  ///
  /// An identifier is returned immediately, and individual results will be
  /// returned via the search.results notification as they become available.
  Future<FindMemberDeclarationsResult> findMemberDeclarations(String name) {
    Map m = {'name': name};
    return _call('search.findMemberDeclarations', m)
        .then(FindMemberDeclarationsResult.parse);
  }

  /// Perform a search for references to members whose name is equal to the
  /// given name. This search does not check to see that there is a member
  /// defined with the given name, so it is able to find references to undefined
  /// members as well.
  ///
  /// An identifier is returned immediately, and individual results will be
  /// returned via the search.results notification as they become available.
  Future<FindMemberReferencesResult> findMemberReferences(String name) {
    Map m = {'name': name};
    return _call('search.findMemberReferences', m)
        .then(FindMemberReferencesResult.parse);
  }

  /// Perform a search for declarations of top-level elements (classes,
  /// typedefs, getters, setters, functions and fields) whose name matches the
  /// given pattern.
  ///
  /// An identifier is returned immediately, and individual results will be
  /// returned via the search.results notification as they become available.
  Future<FindTopLevelDeclarationsResult> findTopLevelDeclarations(
      String pattern) {
    Map m = {'pattern': pattern};
    return _call('search.findTopLevelDeclarations', m)
        .then(FindTopLevelDeclarationsResult.parse);
  }

  /// Return the type hierarchy of the class declared or referenced at the given
  /// location.
  Future<TypeHierarchyResult> getTypeHierarchy(String file, int offset,
      {bool superOnly}) {
    Map m = {'file': file, 'offset': offset};
    if (superOnly != null) m['superOnly'] = superOnly;
    return _call('search.getTypeHierarchy', m).then(TypeHierarchyResult.parse);
  }
}

class SearchResults {
  static SearchResults parse(Map m) => new SearchResults(
      m['id'],
      m['results'] == null
          ? null
          : new List.from(m['results'].map((obj) => SearchResult.parse(obj))),
      m['isLast']);

  /// The id associated with the search.
  final String id;

  /// The search results being reported.
  final List<SearchResult> results;

  /// True if this is that last set of results that will be returned for the
  /// indicated search.
  final bool isLast;

  SearchResults(this.id, this.results, this.isLast);
}

class FindElementReferencesResult {
  static FindElementReferencesResult parse(Map m) =>
      new FindElementReferencesResult(
          id: m['id'], element: Element.parse(m['element']));

  /// The identifier used to associate results with this search request.
  ///
  /// If no element was found at the given location, this field will be absent,
  /// and no results will be reported via the search.results notification.
  @optional
  final String id;

  /// The element referenced or defined at the given offset and whose references
  /// will be returned in the search results.
  ///
  /// If no element was found at the given location, this field will be absent.
  @optional
  final Element element;

  FindElementReferencesResult({this.id, this.element});
}

class FindMemberDeclarationsResult {
  static FindMemberDeclarationsResult parse(Map m) =>
      new FindMemberDeclarationsResult(m['id']);

  /// The identifier used to associate results with this search request.
  final String id;

  FindMemberDeclarationsResult(this.id);
}

class FindMemberReferencesResult {
  static FindMemberReferencesResult parse(Map m) =>
      new FindMemberReferencesResult(m['id']);

  /// The identifier used to associate results with this search request.
  final String id;

  FindMemberReferencesResult(this.id);
}

class FindTopLevelDeclarationsResult {
  static FindTopLevelDeclarationsResult parse(Map m) =>
      new FindTopLevelDeclarationsResult(m['id']);

  /// The identifier used to associate results with this search request.
  final String id;

  FindTopLevelDeclarationsResult(this.id);
}

class TypeHierarchyResult {
  static TypeHierarchyResult parse(Map m) => new TypeHierarchyResult(
      hierarchyItems: m['hierarchyItems'] == null
          ? null
          : new List.from(
              m['hierarchyItems'].map((obj) => TypeHierarchyItem.parse(obj))));

  /// A list of the types in the requested hierarchy. The first element of the
  /// list is the item representing the type for which the hierarchy was
  /// requested. The index of other elements of the list is unspecified, but
  /// correspond to the integers used to reference supertype and subtype items
  /// within the items.
  ///
  /// This field will be absent if the code at the given file and offset does
  /// not represent a type, or if the file has not been sufficiently analyzed to
  /// allow a type hierarchy to be produced.
  @optional
  final List<TypeHierarchyItem> hierarchyItems;

  TypeHierarchyResult({this.hierarchyItems});
}

// edit domain

/// The edit domain contains commands related to edits that can be applied to
/// the code.
class EditDomain extends Domain {
  EditDomain(AnalysisServer server) : super(server, 'edit');

  /// Format the contents of a single file. The currently selected region of
  /// text is passed in so that the selection can be preserved across the
  /// formatting operation. The updated selection will be as close to matching
  /// the original as possible, but whitespace at the beginning or end of the
  /// selected region will be ignored. If preserving selection information is
  /// not required, zero (0) can be specified for both the selection offset and
  /// selection length.
  ///
  /// If a request is made for a file which does not exist, or which is not
  /// currently subject to analysis (e.g. because it is not associated with any
  /// analysis root specified to analysis.setAnalysisRoots), an error of type
  /// `FORMAT_INVALID_FILE` will be generated. If the source contains syntax
  /// errors, an error of type `FORMAT_WITH_ERRORS` will be generated.
  Future<FormatResult> format(
      String file, int selectionOffset, int selectionLength,
      {int lineLength}) {
    Map m = {
      'file': file,
      'selectionOffset': selectionOffset,
      'selectionLength': selectionLength
    };
    if (lineLength != null) m['lineLength'] = lineLength;
    return _call('edit.format', m).then(FormatResult.parse);
  }

  /// Return the set of assists that are available at the given location. An
  /// assist is distinguished from a refactoring primarily by the fact that it
  /// affects a single file and does not require user input in order to be
  /// performed.
  Future<AssistsResult> getAssists(String file, int offset, int length) {
    Map m = {'file': file, 'offset': offset, 'length': length};
    return _call('edit.getAssists', m).then(AssistsResult.parse);
  }

  /// Get a list of the kinds of refactorings that are valid for the given
  /// selection in the given file.
  Future<AvailableRefactoringsResult> getAvailableRefactorings(
      String file, int offset, int length) {
    Map m = {'file': file, 'offset': offset, 'length': length};
    return _call('edit.getAvailableRefactorings', m)
        .then(AvailableRefactoringsResult.parse);
  }

  /// Return the set of fixes that are available for the errors at a given
  /// offset in a given file.
  Future<FixesResult> getFixes(String file, int offset) {
    Map m = {'file': file, 'offset': offset};
    return _call('edit.getFixes', m).then(FixesResult.parse);
  }

  /// Get the changes required to perform a refactoring.
  ///
  /// If another refactoring request is received during the processing of this
  /// one, an error of type `REFACTORING_REQUEST_CANCELLED` will be generated.
  Future<RefactoringResult> getRefactoring(
      String kind, String file, int offset, int length, bool validateOnly,
      {RefactoringOptions options}) {
    Map m = {
      'kind': kind,
      'file': file,
      'offset': offset,
      'length': length,
      'validateOnly': validateOnly
    };
    if (options != null) m['options'] = options;
    return _call('edit.getRefactoring', m).then(RefactoringResult.parse);
  }

  /// Get the changes required to convert the partial statement at the given
  /// location into a syntactically valid statement. If the current statement is
  /// already valid the change will insert a newline plus appropriate
  /// indentation at the end of the line containing the offset. If a change that
  /// makes the statement valid cannot be determined (perhaps because it has not
  /// yet been implemented) the statement will be considered already valid and
  /// the appropriate change returned.
  @experimental
  Future<StatementCompletionResult> getStatementCompletion(
      String file, int offset) {
    Map m = {'file': file, 'offset': offset};
    return _call('edit.getStatementCompletion', m)
        .then(StatementCompletionResult.parse);
  }

  /// Sort all of the directives, unit and class members of the given Dart file.
  ///
  /// If a request is made for a file that does not exist, does not belong to an
  /// analysis root or is not a Dart file, `SORT_MEMBERS_INVALID_FILE` will be
  /// generated.
  ///
  /// If the Dart file has scan or parse errors, `SORT_MEMBERS_PARSE_ERRORS`
  /// will be generated.
  Future<SortMembersResult> sortMembers(String file) {
    Map m = {'file': file};
    return _call('edit.sortMembers', m).then(SortMembersResult.parse);
  }

  /// Organizes all of the directives - removes unused imports and sorts
  /// directives of the given Dart file according to the (Dart Style
  /// Guide)[https://www.dartlang.org/articles/style-guide/].
  ///
  /// If a request is made for a file that does not exist, does not belong to an
  /// analysis root or is not a Dart file, `FILE_NOT_ANALYZED` will be
  /// generated.
  ///
  /// If directives of the Dart file cannot be organized, for example because it
  /// has scan or parse errors, or by other reasons, `ORGANIZE_DIRECTIVES_ERROR`
  /// will be generated. The message will provide details about the reason.
  Future<OrganizeDirectivesResult> organizeDirectives(String file) {
    Map m = {'file': file};
    return _call('edit.organizeDirectives', m)
        .then(OrganizeDirectivesResult.parse);
  }
}

class FormatResult {
  static FormatResult parse(Map m) => new FormatResult(
      m['edits'] == null
          ? null
          : new List.from(m['edits'].map((obj) => SourceEdit.parse(obj))),
      m['selectionOffset'],
      m['selectionLength']);

  /// The edit(s) to be applied in order to format the code. The list will be
  /// empty if the code was already formatted (there are no changes).
  final List<SourceEdit> edits;

  /// The offset of the selection after formatting the code.
  final int selectionOffset;

  /// The length of the selection after formatting the code.
  final int selectionLength;

  FormatResult(this.edits, this.selectionOffset, this.selectionLength);
}

class AssistsResult {
  static AssistsResult parse(Map m) => new AssistsResult(m['assists'] == null
      ? null
      : new List.from(m['assists'].map((obj) => SourceChange.parse(obj))));

  /// The assists that are available at the given location.
  final List<SourceChange> assists;

  AssistsResult(this.assists);
}

class AvailableRefactoringsResult {
  static AvailableRefactoringsResult parse(Map m) =>
      new AvailableRefactoringsResult(
          m['kinds'] == null ? null : new List.from(m['kinds']));

  /// The kinds of refactorings that are valid for the given selection.
  final List<String> kinds;

  AvailableRefactoringsResult(this.kinds);
}

class FixesResult {
  static FixesResult parse(Map m) => new FixesResult(m['fixes'] == null
      ? null
      : new List.from(m['fixes'].map((obj) => AnalysisErrorFixes.parse(obj))));

  /// The fixes that are available for the errors at the given offset.
  final List<AnalysisErrorFixes> fixes;

  FixesResult(this.fixes);
}

class RefactoringResult {
  static RefactoringResult parse(Map m) => new RefactoringResult(
      m['initialProblems'] == null
          ? null
          : new List.from(
              m['initialProblems'].map((obj) => RefactoringProblem.parse(obj))),
      m['optionsProblems'] == null
          ? null
          : new List.from(
              m['optionsProblems'].map((obj) => RefactoringProblem.parse(obj))),
      m['finalProblems'] == null
          ? null
          : new List.from(
              m['finalProblems'].map((obj) => RefactoringProblem.parse(obj))),
      feedback: RefactoringFeedback.parse(m['feedback']),
      change: SourceChange.parse(m['change']),
      potentialEdits: m['potentialEdits'] == null
          ? null
          : new List.from(m['potentialEdits']));

  /// The initial status of the refactoring, i.e. problems related to the
  /// context in which the refactoring is requested. The array will be empty if
  /// there are no known problems.
  final List<RefactoringProblem> initialProblems;

  /// The options validation status, i.e. problems in the given options, such as
  /// light-weight validation of a new name, flags compatibility, etc. The array
  /// will be empty if there are no known problems.
  final List<RefactoringProblem> optionsProblems;

  /// The final status of the refactoring, i.e. problems identified in the
  /// result of a full, potentially expensive validation and / or change
  /// creation. The array will be empty if there are no known problems.
  final List<RefactoringProblem> finalProblems;

  /// Data used to provide feedback to the user. The structure of the data is
  /// dependent on the kind of refactoring being created. The data that is
  /// returned is documented in the section titled
  /// (Refactorings)[#refactorings], labeled as "Feedback".
  @optional
  final RefactoringFeedback feedback;

  /// The changes that are to be applied to affect the refactoring. This field
  /// will be omitted if there are problems that prevent a set of changes from
  /// being computed, such as having no options specified for a refactoring that
  /// requires them, or if only validation was requested.
  @optional
  final SourceChange change;

  /// The ids of source edits that are not known to be valid. An edit is not
  /// known to be valid if there was insufficient type information for the
  /// server to be able to determine whether or not the code needs to be
  /// modified, such as when a member is being renamed and there is a reference
  /// to a member from an unknown type. This field will be omitted if the change
  /// field is omitted or if there are no potential edits for the refactoring.
  @optional
  final List<String> potentialEdits;

  RefactoringResult(
      this.initialProblems, this.optionsProblems, this.finalProblems,
      {this.feedback, this.change, this.potentialEdits});
}

class StatementCompletionResult {
  static StatementCompletionResult parse(Map m) =>
      new StatementCompletionResult(
          SourceChange.parse(m['change']), m['whitespaceOnly']);

  /// The change to be applied in order to complete the statement.
  final SourceChange change;

  /// Will be true if the change contains nothing but whitespace characters, or
  /// is empty.
  final bool whitespaceOnly;

  StatementCompletionResult(this.change, this.whitespaceOnly);
}

class SortMembersResult {
  static SortMembersResult parse(Map m) =>
      new SortMembersResult(SourceFileEdit.parse(m['edit']));

  /// The file edit that is to be applied to the given file to effect the
  /// sorting.
  final SourceFileEdit edit;

  SortMembersResult(this.edit);
}

class OrganizeDirectivesResult {
  static OrganizeDirectivesResult parse(Map m) =>
      new OrganizeDirectivesResult(SourceFileEdit.parse(m['edit']));

  /// The file edit that is to be applied to the given file to effect the
  /// organizing.
  final SourceFileEdit edit;

  OrganizeDirectivesResult(this.edit);
}

// execution domain

/// The execution domain contains commands related to providing an execution or
/// debugging experience.
class ExecutionDomain extends Domain {
  ExecutionDomain(AnalysisServer server) : super(server, 'execution');

  /// Reports information needed to allow a single file to be launched.
  ///
  /// This notification is not subscribed to by default. Clients can subscribe
  /// by including the value "LAUNCH_DATA" in the list of services passed in an
  /// `execution.setSubscriptions` request.
  Stream<ExecutionLaunchData> get onLaunchData {
    return _listen('execution.launchData', ExecutionLaunchData.parse);
  }

  /// Create an execution context for the executable file with the given path.
  /// The context that is created will persist until execution.deleteContext is
  /// used to delete it. Clients, therefore, are responsible for managing the
  /// lifetime of execution contexts.
  Future<CreateContextResult> createContext(String contextRoot) {
    Map m = {'contextRoot': contextRoot};
    return _call('execution.createContext', m).then(CreateContextResult.parse);
  }

  /// Delete the execution context with the given identifier. The context id is
  /// no longer valid after this command. The server is allowed to re-use ids
  /// when they are no longer valid.
  Future deleteContext(String id) =>
      _call('execution.deleteContext', {'id': id});

  /// Map a URI from the execution context to the file that it corresponds to,
  /// or map a file to the URI that it corresponds to in the execution context.
  ///
  /// Exactly one of the file and uri fields must be provided. If both fields
  /// are provided, then an error of type `INVALID_PARAMETER` will be generated.
  /// Similarly, if neither field is provided, then an error of type
  /// `INVALID_PARAMETER` will be generated.
  ///
  /// If the file field is provided and the value is not the path of a file
  /// (either the file does not exist or the path references something other
  /// than a file), then an error of type `INVALID_PARAMETER` will be generated.
  ///
  /// If the uri field is provided and the value is not a valid URI or if the
  /// URI references something that is not a file (either a file that does not
  /// exist or something other than a file), then an error of type
  /// `INVALID_PARAMETER` will be generated.
  ///
  /// If the contextRoot used to create the execution context does not exist,
  /// then an error of type `INVALID_EXECUTION_CONTEXT` will be generated.
  Future<MapUriResult> mapUri(String id, {String file, String uri}) {
    Map m = {'id': id};
    if (file != null) m['file'] = file;
    if (uri != null) m['uri'] = uri;
    return _call('execution.mapUri', m).then(MapUriResult.parse);
  }

  @deprecated
  Future setSubscriptions(List<String> subscriptions) =>
      _call('execution.setSubscriptions', {'subscriptions': subscriptions});
}

class ExecutionLaunchData {
  static ExecutionLaunchData parse(Map m) => new ExecutionLaunchData(m['file'],
      kind: m['kind'],
      referencedFiles: m['referencedFiles'] == null
          ? null
          : new List.from(m['referencedFiles']));

  /// The file for which launch data is being provided. This will either be a
  /// Dart library or an HTML file.
  final String file;

  /// The kind of the executable file. This field is omitted if the file is not
  /// a Dart file.
  @optional
  final String kind;

  /// A list of the Dart files that are referenced by the file. This field is
  /// omitted if the file is not an HTML file.
  @optional
  final List<String> referencedFiles;

  ExecutionLaunchData(this.file, {this.kind, this.referencedFiles});
}

class CreateContextResult {
  static CreateContextResult parse(Map m) => new CreateContextResult(m['id']);

  /// The identifier used to refer to the execution context that was created.
  final String id;

  CreateContextResult(this.id);
}

class MapUriResult {
  static MapUriResult parse(Map m) =>
      new MapUriResult(file: m['file'], uri: m['uri']);

  /// The file to which the URI was mapped. This field is omitted if the uri
  /// field was not given in the request.
  @optional
  final String file;

  /// The URI to which the file path was mapped. This field is omitted if the
  /// file field was not given in the request.
  @optional
  final String uri;

  MapUriResult({this.file, this.uri});
}

// diagnostic domain

/// The diagnostic domain contains server diagnostics APIs.
class DiagnosticDomain extends Domain {
  DiagnosticDomain(AnalysisServer server) : super(server, 'diagnostic');

  /// Return server diagnostics.
  Future<DiagnosticsResult> getDiagnostics() =>
      _call('diagnostic.getDiagnostics').then(DiagnosticsResult.parse);

  /// Return the port of the diagnostic web server. If the server is not running
  /// this call will start the server. If unable to start the diagnostic web
  /// server, this call will return an error of
  /// `DEBUG_PORT_COULD_NOT_BE_OPENED`.
  Future<ServerPortResult> getServerPort() =>
      _call('diagnostic.getServerPort').then(ServerPortResult.parse);
}

class DiagnosticsResult {
  static DiagnosticsResult parse(Map m) =>
      new DiagnosticsResult(m['contexts'] == null
          ? null
          : new List.from(m['contexts'].map((obj) => ContextData.parse(obj))));

  /// The list of analysis contexts.
  final List<ContextData> contexts;

  DiagnosticsResult(this.contexts);
}

class ServerPortResult {
  static ServerPortResult parse(Map m) => new ServerPortResult(m['port']);

  /// The diagnostic server port.
  final int port;

  ServerPortResult(this.port);
}

// type definitions

/// A directive to begin overlaying the contents of a file. The supplied content
/// will be used for analysis in place of the file contents in the filesystem.
///
/// If this directive is used on a file that already has a file content overlay,
/// the old overlay is discarded and replaced with the new one.
class AddContentOverlay extends ContentOverlayType implements Jsonable {
  static AddContentOverlay parse(Map m) {
    if (m == null) return null;
    return new AddContentOverlay(m['content']);
  }

  /// The new content of the file.
  final String content;

  AddContentOverlay(this.content) : super('add');

  Map toMap() => _stripNullValues({'type': type, 'content': content});
}

/// An indication of an error, warning, or hint that was produced by the
/// analysis.
class AnalysisError {
  static AnalysisError parse(Map m) {
    if (m == null) return null;
    return new AnalysisError(m['severity'], m['type'],
        Location.parse(m['location']), m['message'], m['code'],
        correction: m['correction'], hasFix: m['hasFix']);
  }

  /// The severity of the error.
  final String severity;

  /// The type of the error.
  final String type;

  /// The location associated with the error.
  final Location location;

  /// The message to be displayed for this error. The message should indicate
  /// what is wrong with the code and why it is wrong.
  final String message;

  /// The name, as a string, of the error code associated with this error.
  final String code;

  /// The correction message to be displayed for this error. The correction
  /// message should indicate how the user can fix the error. The field is
  /// omitted if there is no correction message associated with the error code.
  @optional
  final String correction;

  /// A hint to indicate to interested clients that this error has an associated
  /// fix (or fixes). The absence of this field implies there are not known to
  /// be fixes. Note that since the operation to calculate whether fixes apply
  /// needs to be performant it is possible that complicated tests will be
  /// skipped and a false negative returned. For this reason, this attribute
  /// should be treated as a "hint". Despite the possibility of false negatives,
  /// no false positives should be returned. If a client sees this flag set they
  /// can proceed with the confidence that there are in fact associated fixes.
  @optional
  final bool hasFix;

  AnalysisError(
      this.severity, this.type, this.location, this.message, this.code,
      {this.correction, this.hasFix});

  operator ==(o) =>
      o is AnalysisError &&
      severity == o.severity &&
      type == o.type &&
      location == o.location &&
      message == o.message &&
      code == o.code &&
      correction == o.correction &&
      hasFix == o.hasFix;

  get hashCode =>
      severity.hashCode ^
      type.hashCode ^
      location.hashCode ^
      message.hashCode ^
      code.hashCode;

  String toString() =>
      '[AnalysisError severity: ${severity}, type: ${type}, location: ${location}, message: ${message}, code: ${code}]';
}

/// A list of fixes associated with a specific error
class AnalysisErrorFixes {
  static AnalysisErrorFixes parse(Map m) {
    if (m == null) return null;
    return new AnalysisErrorFixes(
        AnalysisError.parse(m['error']),
        m['fixes'] == null
            ? null
            : new List.from(m['fixes'].map((obj) => SourceChange.parse(obj))));
  }

  /// The error with which the fixes are associated.
  final AnalysisError error;

  /// The fixes associated with the error.
  final List<SourceChange> fixes;

  AnalysisErrorFixes(this.error, this.fixes);
}

@deprecated
class AnalysisOptions implements Jsonable {
  static AnalysisOptions parse(Map m) {
    if (m == null) return null;
    return new AnalysisOptions(
        enableAsync: m['enableAsync'],
        enableDeferredLoading: m['enableDeferredLoading'],
        enableEnums: m['enableEnums'],
        enableNullAwareOperators: m['enableNullAwareOperators'],
        enableSuperMixins: m['enableSuperMixins'],
        generateDart2jsHints: m['generateDart2jsHints'],
        generateHints: m['generateHints'],
        generateLints: m['generateLints']);
  }

  @deprecated
  @optional
  final bool enableAsync;
  @deprecated
  @optional
  final bool enableDeferredLoading;
  @deprecated
  @optional
  final bool enableEnums;
  @deprecated
  @optional
  final bool enableNullAwareOperators;

  /// True if the client wants to enable support for the proposed "less
  /// restricted mixins" proposal (DEP 34).
  @optional
  final bool enableSuperMixins;

  /// True if hints that are specific to dart2js should be generated. This
  /// option is ignored if generateHints is false.
  @optional
  final bool generateDart2jsHints;

  /// True if hints should be generated as part of generating errors and
  /// warnings.
  @optional
  final bool generateHints;

  /// True if lints should be generated as part of generating errors and
  /// warnings.
  @optional
  final bool generateLints;

  AnalysisOptions(
      {this.enableAsync,
      this.enableDeferredLoading,
      this.enableEnums,
      this.enableNullAwareOperators,
      this.enableSuperMixins,
      this.generateDart2jsHints,
      this.generateHints,
      this.generateLints});

  Map toMap() => _stripNullValues({
        'enableAsync': enableAsync,
        'enableDeferredLoading': enableDeferredLoading,
        'enableEnums': enableEnums,
        'enableNullAwareOperators': enableNullAwareOperators,
        'enableSuperMixins': enableSuperMixins,
        'generateDart2jsHints': generateDart2jsHints,
        'generateHints': generateHints,
        'generateLints': generateLints
      });
}

/// An indication of the current state of analysis.
class AnalysisStatus {
  static AnalysisStatus parse(Map m) {
    if (m == null) return null;
    return new AnalysisStatus(m['isAnalyzing'],
        analysisTarget: m['analysisTarget']);
  }

  /// True if analysis is currently being performed.
  final bool isAnalyzing;

  /// The name of the current target of analysis. This field is omitted if
  /// analyzing is false.
  @optional
  final String analysisTarget;

  AnalysisStatus(this.isAnalyzing, {this.analysisTarget});

  String toString() => '[AnalysisStatus isAnalyzing: ${isAnalyzing}]';
}

/// A directive to modify an existing file content overlay. One or more ranges
/// of text are deleted from the old file content overlay and replaced with new
/// text.
///
/// The edits are applied in the order in which they occur in the list. This
/// means that the offset of each edit must be correct under the assumption that
/// all previous edits have been applied.
///
/// It is an error to use this overlay on a file that does not yet have a file
/// content overlay or that has had its overlay removed via
/// (RemoveContentOverlay)[#type_RemoveContentOverlay].
///
/// If any of the edits cannot be applied due to its offset or length being out
/// of range, an INVALID_OVERLAY_CHANGE error will be reported.
class ChangeContentOverlay extends ContentOverlayType implements Jsonable {
  static ChangeContentOverlay parse(Map m) {
    if (m == null) return null;
    return new ChangeContentOverlay(m['edits'] == null
        ? null
        : new List.from(m['edits'].map((obj) => SourceEdit.parse(obj))));
  }

  /// The edits to be applied to the file.
  final List<SourceEdit> edits;

  ChangeContentOverlay(this.edits) : super('change');

  Map toMap() => _stripNullValues({'type': type, 'edits': edits});
}

/// A suggestion for how to complete partially entered text. Many of the fields
/// are optional, depending on the kind of element being suggested.
class CompletionSuggestion implements Jsonable {
  static CompletionSuggestion parse(Map m) {
    if (m == null) return null;
    return new CompletionSuggestion(
        m['kind'],
        m['relevance'],
        m['completion'],
        m['selectionOffset'],
        m['selectionLength'],
        m['isDeprecated'],
        m['isPotential'],
        docSummary: m['docSummary'],
        docComplete: m['docComplete'],
        declaringType: m['declaringType'],
        defaultArgumentListString: m['defaultArgumentListString'],
        defaultArgumentListTextRanges:
            m['defaultArgumentListTextRanges'] == null
                ? null
                : new List.from(m['defaultArgumentListTextRanges']),
        element: Element.parse(m['element']),
        returnType: m['returnType'],
        parameterNames: m['parameterNames'] == null
            ? null
            : new List.from(m['parameterNames']),
        parameterTypes: m['parameterTypes'] == null
            ? null
            : new List.from(m['parameterTypes']),
        requiredParameterCount: m['requiredParameterCount'],
        hasNamedParameters: m['hasNamedParameters'],
        parameterName: m['parameterName'],
        parameterType: m['parameterType'],
        importUri: m['importUri']);
  }

  /// The kind of element being suggested.
  final String kind;

  /// The relevance of this completion suggestion where a higher number
  /// indicates a higher relevance.
  final int relevance;

  /// The identifier to be inserted if the suggestion is selected. If the
  /// suggestion is for a method or function, the client might want to
  /// additionally insert a template for the parameters. The information
  /// required in order to do so is contained in other fields.
  final String completion;

  /// The offset, relative to the beginning of the completion, of where the
  /// selection should be placed after insertion.
  final int selectionOffset;

  /// The number of characters that should be selected after insertion.
  final int selectionLength;

  /// True if the suggested element is deprecated.
  final bool isDeprecated;

  /// True if the element is not known to be valid for the target. This happens
  /// if the type of the target is dynamic.
  final bool isPotential;

  /// An abbreviated version of the Dartdoc associated with the element being
  /// suggested, This field is omitted if there is no Dartdoc associated with
  /// the element.
  @optional
  final String docSummary;

  /// The Dartdoc associated with the element being suggested, This field is
  /// omitted if there is no Dartdoc associated with the element.
  @optional
  final String docComplete;

  /// The class that declares the element being suggested. This field is omitted
  /// if the suggested element is not a member of a class.
  @optional
  final String declaringType;

  /// A default String for use in generating argument list source contents on
  /// the client side.
  @optional
  final String defaultArgumentListString;

  /// Pairs of offsets and lengths describing 'defaultArgumentListString' text
  /// ranges suitable for use by clients to set up linked edits of default
  /// argument source contents. For example, given an argument list string 'x,
  /// y', the corresponding text range [0, 1, 3, 1], indicates two text ranges
  /// of length 1, starting at offsets 0 and 3. Clients can use these ranges to
  /// treat the 'x' and 'y' values specially for linked edits.
  @optional
  final List<int> defaultArgumentListTextRanges;

  /// Information about the element reference being suggested.
  @optional
  final Element element;

  /// The return type of the getter, function or method or the type of the field
  /// being suggested. This field is omitted if the suggested element is not a
  /// getter, function or method.
  @optional
  final String returnType;

  /// The names of the parameters of the function or method being suggested.
  /// This field is omitted if the suggested element is not a setter, function
  /// or method.
  @optional
  final List<String> parameterNames;

  /// The types of the parameters of the function or method being suggested.
  /// This field is omitted if the parameterNames field is omitted.
  @optional
  final List<String> parameterTypes;

  /// The number of required parameters for the function or method being
  /// suggested. This field is omitted if the parameterNames field is omitted.
  @optional
  final int requiredParameterCount;

  /// True if the function or method being suggested has at least one named
  /// parameter. This field is omitted if the parameterNames field is omitted.
  @optional
  final bool hasNamedParameters;

  /// The name of the optional parameter being suggested. This field is omitted
  /// if the suggestion is not the addition of an optional argument within an
  /// argument list.
  @optional
  final String parameterName;

  /// The type of the options parameter being suggested. This field is omitted
  /// if the parameterName field is omitted.
  @optional
  final String parameterType;

  /// The import to be added if the suggestion is out of scope and needs an
  /// import to be added to be in scope.
  @optional
  final String importUri;

  CompletionSuggestion(
      this.kind,
      this.relevance,
      this.completion,
      this.selectionOffset,
      this.selectionLength,
      this.isDeprecated,
      this.isPotential,
      {this.docSummary,
      this.docComplete,
      this.declaringType,
      this.defaultArgumentListString,
      this.defaultArgumentListTextRanges,
      this.element,
      this.returnType,
      this.parameterNames,
      this.parameterTypes,
      this.requiredParameterCount,
      this.hasNamedParameters,
      this.parameterName,
      this.parameterType,
      this.importUri});

  Map toMap() => _stripNullValues({
        'kind': kind,
        'relevance': relevance,
        'completion': completion,
        'selectionOffset': selectionOffset,
        'selectionLength': selectionLength,
        'isDeprecated': isDeprecated,
        'isPotential': isPotential,
        'docSummary': docSummary,
        'docComplete': docComplete,
        'declaringType': declaringType,
        'defaultArgumentListString': defaultArgumentListString,
        'defaultArgumentListTextRanges': defaultArgumentListTextRanges,
        'element': element,
        'returnType': returnType,
        'parameterNames': parameterNames,
        'parameterTypes': parameterTypes,
        'requiredParameterCount': requiredParameterCount,
        'hasNamedParameters': hasNamedParameters,
        'parameterName': parameterName,
        'parameterType': parameterType,
        'importUri': importUri
      });

  String toString() =>
      '[CompletionSuggestion kind: ${kind}, relevance: ${relevance}, completion: ${completion}, selectionOffset: ${selectionOffset}, selectionLength: ${selectionLength}, isDeprecated: ${isDeprecated}, isPotential: ${isPotential}]';
}

/// Information about an analysis context.
class ContextData {
  static ContextData parse(Map m) {
    if (m == null) return null;
    return new ContextData(
        m['name'],
        m['explicitFileCount'],
        m['implicitFileCount'],
        m['workItemQueueLength'],
        m['cacheEntryExceptions'] == null
            ? null
            : new List.from(m['cacheEntryExceptions']));
  }

  /// The name of the context.
  final String name;

  /// Explicitly analyzed files.
  final int explicitFileCount;

  /// Implicitly analyzed files.
  final int implicitFileCount;

  /// The number of work items in the queue.
  final int workItemQueueLength;

  /// Exceptions associated with cache entries.
  final List<String> cacheEntryExceptions;

  ContextData(this.name, this.explicitFileCount, this.implicitFileCount,
      this.workItemQueueLength, this.cacheEntryExceptions);
}

/// Information about an element (something that can be declared in code).
class Element {
  static Element parse(Map m) {
    if (m == null) return null;
    return new Element(m['kind'], m['name'], m['flags'],
        location: Location.parse(m['location']),
        parameters: m['parameters'],
        returnType: m['returnType'],
        typeParameters: m['typeParameters']);
  }

  /// The kind of the element.
  final String kind;

  /// The name of the element. This is typically used as the label in the
  /// outline.
  final String name;

  /// A bit-map containing the following flags:
  final int flags;

  /// The location of the name in the declaration of the element.
  @optional
  final Location location;

  /// The parameter list for the element. If the element is not a method or
  /// function this field will not be defined. If the element doesn't have
  /// parameters (e.g. getter), this field will not be defined. If the element
  /// has zero parameters, this field will have a value of "()".
  @optional
  final String parameters;

  /// The return type of the element. If the element is not a method or function
  /// this field will not be defined. If the element does not have a declared
  /// return type, this field will contain an empty string.
  @optional
  final String returnType;

  /// The type parameter list for the element. If the element doesn't have type
  /// parameters, this field will not be defined.
  @optional
  final String typeParameters;

  Element(this.kind, this.name, this.flags,
      {this.location, this.parameters, this.returnType, this.typeParameters});

  String toString() =>
      '[Element kind: ${kind}, name: ${name}, flags: ${flags}]';
}

/// A description of an executable file.
class ExecutableFile {
  static ExecutableFile parse(Map m) {
    if (m == null) return null;
    return new ExecutableFile(m['file'], m['kind']);
  }

  /// The path of the executable file.
  final String file;

  /// The kind of the executable file.
  final String kind;

  ExecutableFile(this.file, this.kind);
}

/// A description of a region that can be folded.
class FoldingRegion {
  static FoldingRegion parse(Map m) {
    if (m == null) return null;
    return new FoldingRegion(m['kind'], m['offset'], m['length']);
  }

  /// The kind of the region.
  final String kind;

  /// The offset of the region to be folded.
  final int offset;

  /// The length of the region to be folded.
  final int length;

  FoldingRegion(this.kind, this.offset, this.length);
}

/// A description of a region that could have special highlighting associated
/// with it.
class HighlightRegion {
  static HighlightRegion parse(Map m) {
    if (m == null) return null;
    return new HighlightRegion(m['type'], m['offset'], m['length']);
  }

  /// The type of highlight associated with the region.
  final String type;

  /// The offset of the region to be highlighted.
  final int offset;

  /// The length of the region to be highlighted.
  final int length;

  HighlightRegion(this.type, this.offset, this.length);
}

/// The hover information associated with a specific location.
class HoverInformation {
  static HoverInformation parse(Map m) {
    if (m == null) return null;
    return new HoverInformation(m['offset'], m['length'],
        containingLibraryPath: m['containingLibraryPath'],
        containingLibraryName: m['containingLibraryName'],
        containingClassDescription: m['containingClassDescription'],
        dartdoc: m['dartdoc'],
        elementDescription: m['elementDescription'],
        elementKind: m['elementKind'],
        isDeprecated: m['isDeprecated'],
        parameter: m['parameter'],
        propagatedType: m['propagatedType'],
        staticType: m['staticType']);
  }

  /// The offset of the range of characters that encompasses the cursor position
  /// and has the same hover information as the cursor position.
  final int offset;

  /// The length of the range of characters that encompasses the cursor position
  /// and has the same hover information as the cursor position.
  final int length;

  /// The path to the defining compilation unit of the library in which the
  /// referenced element is declared. This data is omitted if there is no
  /// referenced element, or if the element is declared inside an HTML file.
  @optional
  final String containingLibraryPath;

  /// The name of the library in which the referenced element is declared. This
  /// data is omitted if there is no referenced element, or if the element is
  /// declared inside an HTML file.
  @optional
  final String containingLibraryName;

  /// A human-readable description of the class declaring the element being
  /// referenced. This data is omitted if there is no referenced element, or if
  /// the element is not a class member.
  @optional
  final String containingClassDescription;

  /// The dartdoc associated with the referenced element. Other than the removal
  /// of the comment delimiters, including leading asterisks in the case of a
  /// block comment, the dartdoc is unprocessed markdown. This data is omitted
  /// if there is no referenced element, or if the element has no dartdoc.
  @optional
  final String dartdoc;

  /// A human-readable description of the element being referenced. This data is
  /// omitted if there is no referenced element.
  @optional
  final String elementDescription;

  /// A human-readable description of the kind of element being referenced (such
  /// as "class" or "function type alias"). This data is omitted if there is no
  /// referenced element.
  @optional
  final String elementKind;

  /// True if the referenced element is deprecated.
  @optional
  final bool isDeprecated;

  /// A human-readable description of the parameter corresponding to the
  /// expression being hovered over. This data is omitted if the location is not
  /// in an argument to a function.
  @optional
  final String parameter;

  /// The name of the propagated type of the expression. This data is omitted if
  /// the location does not correspond to an expression or if there is no
  /// propagated type information.
  @optional
  final String propagatedType;

  /// The name of the static type of the expression. This data is omitted if the
  /// location does not correspond to an expression.
  @optional
  final String staticType;

  HoverInformation(this.offset, this.length,
      {this.containingLibraryPath,
      this.containingLibraryName,
      this.containingClassDescription,
      this.dartdoc,
      this.elementDescription,
      this.elementKind,
      this.isDeprecated,
      this.parameter,
      this.propagatedType,
      this.staticType});
}

/// A description of a class that is implemented or extended.
class ImplementedClass {
  static ImplementedClass parse(Map m) {
    if (m == null) return null;
    return new ImplementedClass(m['offset'], m['length']);
  }

  /// The offset of the name of the implemented class.
  final int offset;

  /// The length of the name of the implemented class.
  final int length;

  ImplementedClass(this.offset, this.length);
}

/// A description of a class member that is implemented or overridden.
class ImplementedMember {
  static ImplementedMember parse(Map m) {
    if (m == null) return null;
    return new ImplementedMember(m['offset'], m['length']);
  }

  /// The offset of the name of the implemented member.
  final int offset;

  /// The length of the name of the implemented member.
  final int length;

  ImplementedMember(this.offset, this.length);
}

/// A collection of positions that should be linked (edited simultaneously) for
/// the purposes of updating code after a source change. For example, if a set
/// of edits introduced a new variable name, the group would contain all of the
/// positions of the variable name so that if the client wanted to let the user
/// edit the variable name after the operation, all occurrences of the name
/// could be edited simultaneously.
class LinkedEditGroup {
  static LinkedEditGroup parse(Map m) {
    if (m == null) return null;
    return new LinkedEditGroup(
        m['positions'] == null
            ? null
            : new List.from(m['positions'].map((obj) => Position.parse(obj))),
        m['length'],
        m['suggestions'] == null
            ? null
            : new List.from(m['suggestions']
                .map((obj) => LinkedEditSuggestion.parse(obj))));
  }

  /// The positions of the regions that should be edited simultaneously.
  final List<Position> positions;

  /// The length of the regions that should be edited simultaneously.
  final int length;

  /// Pre-computed suggestions for what every region might want to be changed
  /// to.
  final List<LinkedEditSuggestion> suggestions;

  LinkedEditGroup(this.positions, this.length, this.suggestions);

  String toString() =>
      '[LinkedEditGroup positions: ${positions}, length: ${length}, suggestions: ${suggestions}]';
}

/// A suggestion of a value that could be used to replace all of the linked edit
/// regions in a LinkedEditGroup.
class LinkedEditSuggestion {
  static LinkedEditSuggestion parse(Map m) {
    if (m == null) return null;
    return new LinkedEditSuggestion(m['value'], m['kind']);
  }

  /// The value that could be used to replace all of the linked edit regions.
  final String value;

  /// The kind of value being proposed.
  final String kind;

  LinkedEditSuggestion(this.value, this.kind);
}

/// A location (character range) within a file.
class Location {
  static Location parse(Map m) {
    if (m == null) return null;
    return new Location(
        m['file'], m['offset'], m['length'], m['startLine'], m['startColumn']);
  }

  /// The file containing the range.
  final String file;

  /// The offset of the range.
  final int offset;

  /// The length of the range.
  final int length;

  /// The one-based index of the line containing the first character of the
  /// range.
  final int startLine;

  /// The one-based index of the column containing the first character of the
  /// range.
  final int startColumn;

  Location(
      this.file, this.offset, this.length, this.startLine, this.startColumn);

  operator ==(o) =>
      o is Location &&
      file == o.file &&
      offset == o.offset &&
      length == o.length &&
      startLine == o.startLine &&
      startColumn == o.startColumn;

  get hashCode =>
      file.hashCode ^
      offset.hashCode ^
      length.hashCode ^
      startLine.hashCode ^
      startColumn.hashCode;

  String toString() =>
      '[Location file: ${file}, offset: ${offset}, length: ${length}, startLine: ${startLine}, startColumn: ${startColumn}]';
}

/// A description of a region from which the user can navigate to the
/// declaration of an element.
class NavigationRegion {
  static NavigationRegion parse(Map m) {
    if (m == null) return null;
    return new NavigationRegion(m['offset'], m['length'],
        m['targets'] == null ? null : new List.from(m['targets']));
  }

  /// The offset of the region from which the user can navigate.
  final int offset;

  /// The length of the region from which the user can navigate.
  final int length;

  /// The indexes of the targets (in the enclosing navigation response) to which
  /// the given region is bound. By opening the target, clients can implement
  /// one form of navigation. This list cannot be empty.
  final List<int> targets;

  NavigationRegion(this.offset, this.length, this.targets);

  String toString() =>
      '[NavigationRegion offset: ${offset}, length: ${length}, targets: ${targets}]';
}

/// A description of a target to which the user can navigate.
class NavigationTarget {
  static NavigationTarget parse(Map m) {
    if (m == null) return null;
    return new NavigationTarget(m['kind'], m['fileIndex'], m['offset'],
        m['length'], m['startLine'], m['startColumn']);
  }

  /// The kind of the element.
  final String kind;

  /// The index of the file (in the enclosing navigation response) to navigate
  /// to.
  final int fileIndex;

  /// The offset of the region to which the user can navigate.
  final int offset;

  /// The length of the region to which the user can navigate.
  final int length;

  /// The one-based index of the line containing the first character of the
  /// region.
  final int startLine;

  /// The one-based index of the column containing the first character of the
  /// region.
  final int startColumn;

  NavigationTarget(this.kind, this.fileIndex, this.offset, this.length,
      this.startLine, this.startColumn);

  String toString() =>
      '[NavigationTarget kind: ${kind}, fileIndex: ${fileIndex}, offset: ${offset}, length: ${length}, startLine: ${startLine}, startColumn: ${startColumn}]';
}

/// A description of the references to a single element within a single file.
class Occurrences {
  static Occurrences parse(Map m) {
    if (m == null) return null;
    return new Occurrences(Element.parse(m['element']),
        m['offsets'] == null ? null : new List.from(m['offsets']), m['length']);
  }

  /// The element that was referenced.
  final Element element;

  /// The offsets of the name of the referenced element within the file.
  final List<int> offsets;

  /// The length of the name of the referenced element.
  final int length;

  Occurrences(this.element, this.offsets, this.length);
}

/// An node in the outline structure of a file.
class Outline {
  static Outline parse(Map m) {
    if (m == null) return null;
    return new Outline(Element.parse(m['element']), m['offset'], m['length'],
        children: m['children'] == null
            ? null
            : new List.from(m['children'].map((obj) => Outline.parse(obj))));
  }

  /// A description of the element represented by this node.
  final Element element;

  /// The offset of the first character of the element. This is different than
  /// the offset in the Element, which if the offset of the name of the element.
  /// It can be used, for example, to map locations in the file back to an
  /// outline.
  final int offset;

  /// The length of the element.
  final int length;

  /// The children of the node. The field will be omitted if the node has no
  /// children.
  @optional
  final List<Outline> children;

  Outline(this.element, this.offset, this.length, {this.children});
}

/// A description of a member that overrides an inherited member.
class Override {
  static Override parse(Map m) {
    if (m == null) return null;
    return new Override(m['offset'], m['length'],
        superclassMember: OverriddenMember.parse(m['superclassMember']),
        interfaceMembers: m['interfaceMembers'] == null
            ? null
            : new List.from(m['interfaceMembers']
                .map((obj) => OverriddenMember.parse(obj))));
  }

  /// The offset of the name of the overriding member.
  final int offset;

  /// The length of the name of the overriding member.
  final int length;

  /// The member inherited from a superclass that is overridden by the
  /// overriding member. The field is omitted if there is no superclass member,
  /// in which case there must be at least one interface member.
  @optional
  final OverriddenMember superclassMember;

  /// The members inherited from interfaces that are overridden by the
  /// overriding member. The field is omitted if there are no interface members,
  /// in which case there must be a superclass member.
  @optional
  final List<OverriddenMember> interfaceMembers;

  Override(this.offset, this.length,
      {this.superclassMember, this.interfaceMembers});
}

/// A description of a member that is being overridden.
class OverriddenMember {
  static OverriddenMember parse(Map m) {
    if (m == null) return null;
    return new OverriddenMember(Element.parse(m['element']), m['className']);
  }

  /// The element that is being overridden.
  final Element element;

  /// The name of the class in which the member is defined.
  final String className;

  OverriddenMember(this.element, this.className);
}

/// A position within a file.
class Position {
  static Position parse(Map m) {
    if (m == null) return null;
    return new Position(m['file'], m['offset']);
  }

  /// The file containing the position.
  final String file;

  /// The offset of the position.
  final int offset;

  Position(this.file, this.offset);

  String toString() => '[Position file: ${file}, offset: ${offset}]';
}

/// An indication of the current state of pub execution.
class PubStatus {
  static PubStatus parse(Map m) {
    if (m == null) return null;
    return new PubStatus(m['isListingPackageDirs']);
  }

  /// True if the server is currently running pub to produce a list of package
  /// directories.
  final bool isListingPackageDirs;

  PubStatus(this.isListingPackageDirs);

  String toString() =>
      '[PubStatus isListingPackageDirs: ${isListingPackageDirs}]';
}

/// A description of a parameter in a method refactoring.
class RefactoringMethodParameter {
  static RefactoringMethodParameter parse(Map m) {
    if (m == null) return null;
    return new RefactoringMethodParameter(m['kind'], m['type'], m['name'],
        id: m['id'], parameters: m['parameters']);
  }

  /// The kind of the parameter.
  final String kind;

  /// The type that should be given to the parameter, or the return type of the
  /// parameter's function type.
  final String type;

  /// The name that should be given to the parameter.
  final String name;

  /// The unique identifier of the parameter. Clients may omit this field for
  /// the parameters they want to add.
  @optional
  final String id;

  /// The parameter list of the parameter's function type. If the parameter is
  /// not of a function type, this field will not be defined. If the function
  /// type has zero parameters, this field will have a value of "()".
  @optional
  final String parameters;

  RefactoringMethodParameter(this.kind, this.type, this.name,
      {this.id, this.parameters});
}

/// A description of a problem related to a refactoring.
class RefactoringProblem {
  static RefactoringProblem parse(Map m) {
    if (m == null) return null;
    return new RefactoringProblem(m['severity'], m['message'],
        location: Location.parse(m['location']));
  }

  /// The severity of the problem being represented.
  final String severity;

  /// A human-readable description of the problem being represented.
  final String message;

  /// The location of the problem being represented. This field is omitted
  /// unless there is a specific location associated with the problem (such as a
  /// location where an element being renamed will be shadowed).
  @optional
  final Location location;

  RefactoringProblem(this.severity, this.message, {this.location});
}

/// A directive to remove an existing file content overlay. After processing
/// this directive, the file contents will once again be read from the file
/// system.
///
/// If this directive is used on a file that doesn't currently have a content
/// overlay, it has no effect.
class RemoveContentOverlay extends ContentOverlayType implements Jsonable {
  static RemoveContentOverlay parse(Map m) {
    if (m == null) return null;
    return new RemoveContentOverlay();
  }

  RemoveContentOverlay() : super('remove');

  Map toMap() => _stripNullValues({'type': type});
}

/// A single result from a search request.
class SearchResult {
  static SearchResult parse(Map m) {
    if (m == null) return null;
    return new SearchResult(
        Location.parse(m['location']),
        m['kind'],
        m['isPotential'],
        m['path'] == null
            ? null
            : new List.from(m['path'].map((obj) => Element.parse(obj))));
  }

  /// The location of the code that matched the search criteria.
  final Location location;

  /// The kind of element that was found or the kind of reference that was
  /// found.
  final String kind;

  /// True if the result is a potential match but cannot be confirmed to be a
  /// match. For example, if all references to a method m defined in some class
  /// were requested, and a reference to a method m from an unknown class were
  /// found, it would be marked as being a potential match.
  final bool isPotential;

  /// The elements that contain the result, starting with the most immediately
  /// enclosing ancestor and ending with the library.
  final List<Element> path;

  SearchResult(this.location, this.kind, this.isPotential, this.path);

  String toString() =>
      '[SearchResult location: ${location}, kind: ${kind}, isPotential: ${isPotential}, path: ${path}]';
}

/// A description of a set of edits that implement a single conceptual change.
class SourceChange {
  static SourceChange parse(Map m) {
    if (m == null) return null;
    return new SourceChange(
        m['message'],
        m['edits'] == null
            ? null
            : new List.from(m['edits'].map((obj) => SourceFileEdit.parse(obj))),
        m['linkedEditGroups'] == null
            ? null
            : new List.from(
                m['linkedEditGroups'].map((obj) => LinkedEditGroup.parse(obj))),
        selection: Position.parse(m['selection']));
  }

  /// A human-readable description of the change to be applied.
  final String message;

  /// A list of the edits used to effect the change, grouped by file.
  final List<SourceFileEdit> edits;

  /// A list of the linked editing groups used to customize the changes that
  /// were made.
  final List<LinkedEditGroup> linkedEditGroups;

  /// The position that should be selected after the edits have been applied.
  @optional
  final Position selection;

  SourceChange(this.message, this.edits, this.linkedEditGroups,
      {this.selection});

  String toString() =>
      '[SourceChange message: ${message}, edits: ${edits}, linkedEditGroups: ${linkedEditGroups}]';
}

/// A description of a single change to a single file.
class SourceEdit implements Jsonable {
  static SourceEdit parse(Map m) {
    if (m == null) return null;
    return new SourceEdit(m['offset'], m['length'], m['replacement'],
        id: m['id']);
  }

  /// The offset of the region to be modified.
  final int offset;

  /// The length of the region to be modified.
  final int length;

  /// The code that is to replace the specified region in the original code.
  final String replacement;

  /// An identifier that uniquely identifies this source edit from other edits
  /// in the same response. This field is omitted unless a containing structure
  /// needs to be able to identify the edit for some reason.
  ///
  /// For example, some refactoring operations can produce edits that might not
  /// be appropriate (referred to as potential edits). Such edits will have an
  /// id so that they can be referenced. Edits in the same response that do not
  /// need to be referenced will not have an id.
  @optional
  final String id;

  SourceEdit(this.offset, this.length, this.replacement, {this.id});

  Map toMap() => _stripNullValues({
        'offset': offset,
        'length': length,
        'replacement': replacement,
        'id': id
      });

  String toString() =>
      '[SourceEdit offset: ${offset}, length: ${length}, replacement: ${replacement}]';
}

/// A description of a set of changes to a single file.
class SourceFileEdit {
  static SourceFileEdit parse(Map m) {
    if (m == null) return null;
    return new SourceFileEdit(
        m['file'],
        m['fileStamp'],
        m['edits'] == null
            ? null
            : new List.from(m['edits'].map((obj) => SourceEdit.parse(obj))));
  }

  /// The file containing the code to be modified.
  final String file;

  /// The modification stamp of the file at the moment when the change was
  /// created, in milliseconds since the "Unix epoch". Will be -1 if the file
  /// did not exist and should be created. The client may use this field to make
  /// sure that the file was not changed since then, so it is safe to apply the
  /// change.
  final int fileStamp;

  /// A list of the edits used to effect the change.
  final List<SourceEdit> edits;

  SourceFileEdit(this.file, this.fileStamp, this.edits);

  String toString() =>
      '[SourceFileEdit file: ${file}, fileStamp: ${fileStamp}, edits: ${edits}]';
}

/// A representation of a class in a type hierarchy.
class TypeHierarchyItem {
  static TypeHierarchyItem parse(Map m) {
    if (m == null) return null;
    return new TypeHierarchyItem(
        Element.parse(m['classElement']),
        m['interfaces'] == null ? null : new List.from(m['interfaces']),
        m['mixins'] == null ? null : new List.from(m['mixins']),
        m['subclasses'] == null ? null : new List.from(m['subclasses']),
        displayName: m['displayName'],
        memberElement: Element.parse(m['memberElement']),
        superclass: m['superclass']);
  }

  /// The class element represented by this item.
  final Element classElement;

  /// The indexes of the items representing the interfaces implemented by this
  /// class. The list will be empty if there are no implemented interfaces.
  final List<int> interfaces;

  /// The indexes of the items representing the mixins referenced by this class.
  /// The list will be empty if there are no classes mixed in to this class.
  final List<int> mixins;

  /// The indexes of the items representing the subtypes of this class. The list
  /// will be empty if there are no subtypes or if this item represents a
  /// supertype of the pivot type.
  final List<int> subclasses;

  /// The name to be displayed for the class. This field will be omitted if the
  /// display name is the same as the name of the element. The display name is
  /// different if there is additional type information to be displayed, such as
  /// type arguments.
  @optional
  final String displayName;

  /// The member in the class corresponding to the member on which the hierarchy
  /// was requested. This field will be omitted if the hierarchy was not
  /// requested for a member or if the class does not have a corresponding
  /// member.
  @optional
  final Element memberElement;

  /// The index of the item representing the superclass of this class. This
  /// field will be omitted if this item represents the class Object.
  @optional
  final int superclass;

  TypeHierarchyItem(
      this.classElement, this.interfaces, this.mixins, this.subclasses,
      {this.displayName, this.memberElement, this.superclass});
}

// refactorings

class Refactorings {
  static const String CONVERT_GETTER_TO_METHOD = 'CONVERT_GETTER_TO_METHOD';
  static const String CONVERT_METHOD_TO_GETTER = 'CONVERT_METHOD_TO_GETTER';
  static const String EXTRACT_LOCAL_VARIABLE = 'EXTRACT_LOCAL_VARIABLE';
  static const String EXTRACT_METHOD = 'EXTRACT_METHOD';
  static const String INLINE_LOCAL_VARIABLE = 'INLINE_LOCAL_VARIABLE';
  static const String INLINE_METHOD = 'INLINE_METHOD';
  static const String MOVE_FILE = 'MOVE_FILE';
  static const String RENAME = 'RENAME';
}

/// Create a local variable initialized by the expression that covers the
/// specified selection.
///
/// It is an error if the selection range is not covered by a complete
/// expression.
class ExtractLocalVariableRefactoringOptions extends RefactoringOptions {
  /// The name that the local variable should be given.
  final String name;

  /// True if all occurrences of the expression within the scope in which the
  /// variable will be defined should be replaced by a reference to the local
  /// variable. The expression used to initiate the refactoring will always be
  /// replaced.
  final bool extractAll;

  ExtractLocalVariableRefactoringOptions({this.name, this.extractAll});

  Map toMap() => _stripNullValues({'name': name, 'extractAll': extractAll});
}

/// Create a method whose body is the specified expression or list of
/// statements, possibly augmented with a return statement.
///
/// It is an error if the range contains anything other than a complete
/// expression (no partial expressions are allowed) or a complete sequence of
/// statements.
class ExtractMethodRefactoringOptions extends RefactoringOptions {
  /// The return type that should be defined for the method.
  final String returnType;

  /// True if a getter should be created rather than a method. It is an error if
  /// this field is true and the list of parameters is non-empty.
  final bool createGetter;

  /// The name that the method should be given.
  final String name;

  /// The parameters that should be defined for the method.
  ///
  /// It is an error if a REQUIRED or NAMED parameter follows a POSITIONAL
  /// parameter. It is an error if a REQUIRED or POSITIONAL parameter follows a
  /// NAMED parameter.
  final List<RefactoringMethodParameter> parameters;

  /// True if all occurrences of the expression or statements should be replaced
  /// by an invocation of the method. The expression or statements used to
  /// initiate the refactoring will always be replaced.
  final bool extractAll;

  ExtractMethodRefactoringOptions(
      {this.returnType,
      this.createGetter,
      this.name,
      this.parameters,
      this.extractAll});

  Map toMap() => _stripNullValues({
        'returnType': returnType,
        'createGetter': createGetter,
        'name': name,
        'parameters': parameters,
        'extractAll': extractAll
      });
}

/// Inline a method in place of one or all references to that method.
///
/// It is an error if the range contains anything other than all or part of the
/// name of a single method.
class InlineMethodRefactoringOptions extends RefactoringOptions {
  /// True if the method being inlined should be removed. It is an error if this
  /// field is true and inlineAll is false.
  final bool deleteSource;

  /// True if all invocations of the method should be inlined, or false if only
  /// the invocation site used to create this refactoring should be inlined.
  final bool inlineAll;

  InlineMethodRefactoringOptions({this.deleteSource, this.inlineAll});

  Map toMap() =>
      _stripNullValues({'deleteSource': deleteSource, 'inlineAll': inlineAll});
}

/// Move the given file and update all of the references to that file and from
/// it. The move operation is supported in general case - for renaming a file in
/// the same folder, moving it to a different folder or both.
///
/// The refactoring must be activated before an actual file moving operation is
/// performed.
///
/// The "offset" and "length" fields from the request are ignored, but the file
/// specified in the request specifies the file to be moved.
class MoveFileRefactoringOptions extends RefactoringOptions {
  /// The new file path to which the given file is being moved.
  final String newFile;

  MoveFileRefactoringOptions({this.newFile});

  Map toMap() => _stripNullValues({'newFile': newFile});
}

/// Rename a given element and all of the references to that element.
///
/// It is an error if the range contains anything other than all or part of the
/// name of a single function (including methods, getters and setters), variable
/// (including fields, parameters and local variables), class or function type.
class RenameRefactoringOptions extends RefactoringOptions {
  /// The name that the element should have after the refactoring.
  final String newName;

  RenameRefactoringOptions({this.newName});

  Map toMap() => _stripNullValues({'newName': newName});
}

// EXTRACT_LOCAL_VARIABLE:
//   @optional coveringExpressionOffsets → List<int>
//   @optional coveringExpressionLengths → List<int>
//   names → List<String>
//   offsets → List<int>
//   lengths → List<int>

// EXTRACT_METHOD:
//   offset → int
//   length → int
//   returnType → String
//   names → List<String>
//   canCreateGetter → bool
//   parameters → List<RefactoringMethodParameter>
//   offsets → List<int>
//   lengths → List<int>

// INLINE_LOCAL_VARIABLE:
//   name → String
//   occurrences → int

// INLINE_METHOD:
//   @optional className → String
//   methodName → String
//   isDeclaration → bool

// RENAME:
//   offset → int
//   length → int
//   elementKindName → String
//   oldName → String

class RefactoringFeedback {
  static RefactoringFeedback parse(Map m) {
    return m == null ? null : new RefactoringFeedback(m);
  }

  final Map _m;

  RefactoringFeedback(this._m);

  operator [](String key) => _m[key];
}
