// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../src/common.dart';
import '../tuneup.dart';

class TrimCommand extends TuneupCommand {
  final List<FileHandler> _handlers = [
    CssFileHandler(),
    DartFileHandler(),
    HtmlFileHandler(),
    JavaScriptFileHandler(),
    MarkdownFileHandler(),
    YamlFileHandler()
  ];

  TrimCommand(Tuneup tuneup)
      : super(tuneup, 'trim', 'trim unwanted whitespace from your source');

  @override
  Future execute(Project project) {
    List<String> ext = List.from(_handlers.expand((h) => h.types));
    List<File> files = project.getSourceFiles(extensions: ext);

    int modifiedCount = 0;

    for (File file in files) {
      String ext = getFileExtension(file.path);

      if (supportsFileType(ext)) {
        String contents = file.readAsStringSync();
        String results = trim(contents, ext);
        if (contents != results) {
          project.print('trimmed ${relativePath(file)}');

          modifiedCount++;
          file.writeAsStringSync(results);
        }
      }
    }

    if (modifiedCount > 0) {
      project
          .print('$modifiedCount ${pluralize("file", modifiedCount)} changed.');
    } else {
      project.print('No files changed.');
    }

    return Future.value();
  }

  bool supportsFileType(String fileExtension) {
    fileExtension = fileExtension.toLowerCase();

    for (var handler in _handlers) {
      if (handler.types.contains(fileExtension)) {
        return true;
      }
    }

    return false;
  }

  String trim(String contents, String fileExtension) {
    fileExtension = fileExtension.toLowerCase();

    for (var handler in _handlers) {
      if (handler.types.contains(fileExtension)) {
        return handler.trim(contents);
      }
    }

    return contents;
  }
}

// TODO: these file handlers need to be cloned before each run

abstract class FileHandler {
  final Set<String> types;
  final List<Converter<String, String>> preConverters = [];
  final List<Converter<String?, String?>> lineConverters = [];
  final List<Converter<String, String>> postConverters = [];

  FileHandler(this.types);

  String trim(String contents) {
    String eol = discoverEol(contents);

    for (Converter converter in preConverters) {
      contents = converter.convert(contents);
    }

    if (lineConverters.isNotEmpty) {
      // TODO: remove this once converters are cloned
      for (var converter in lineConverters) {
        converter.convert(null);
      }

      List<String> lines = contents.split(eol);
      List<String> results = [];

      for (String line in lines) {
        String? result = line;
        for (var converter in lineConverters) {
          result = converter.convert(result);
          if (result == null) break;
        }

        if (result != null) {
          results.add(result);
        }
      }

      contents = results.join(eol);
    }

    for (var converter in postConverters) {
      contents = converter.convert(contents);
    }

    return contents;
  }
}

/// Make sure we end with one eol at eof.
class EndsWithEOLConverter extends Converter<String, String> {
  @override
  String convert(String input) {
    String eol = discoverEol(input);
    input = input.trimRight() + eol;
    return input;
  }
}

/// Remove any whitespace at the end of the line.
class RightTrimLine extends Converter<String?, String?> {
  @override
  String? convert(String? input) => input?.trimRight();
}

/// Remove double blank lines.
class RemoveDoubleBlankConverter extends Converter<String?, String?> {
  bool _lastWasBlank = false;

  @override
  String? convert(String? input) {
    if (input == null) {
      _lastWasBlank = false;
      return null;
    }

    if (input.isEmpty) {
      if (_lastWasBlank) {
        return null;
      } else {
        _lastWasBlank = true;
      }
    } else {
      _lastWasBlank = false;
    }

    return input;
  }
}

class CssFileHandler extends FileHandler {
  CssFileHandler() : super({'css', 'scss'}) {
    lineConverters.add(RightTrimLine());
    lineConverters.add(RemoveDoubleBlankConverter());
    postConverters.add(EndsWithEOLConverter());
  }
}

class DartFileHandler extends FileHandler {
  DartFileHandler() : super({'dart'}) {
    // TODO: This will not properly handle multi-line strings.
    lineConverters.add(RightTrimLine());

    // TODO: This will not properly handle multi-line strings.
    lineConverters.add(RemoveDoubleBlankConverter());

    postConverters.add(EndsWithEOLConverter());
  }
}

class HtmlFileHandler extends FileHandler {
  HtmlFileHandler() : super({'htm', 'html'}) {
    lineConverters.add(RightTrimLine());
    lineConverters.add(RemoveDoubleBlankConverter());
    postConverters.add(EndsWithEOLConverter());
  }
}

class JavaScriptFileHandler extends FileHandler {
  JavaScriptFileHandler() : super({'js'}) {
    lineConverters.add(RightTrimLine());
    lineConverters.add(RemoveDoubleBlankConverter());
    postConverters.add(EndsWithEOLConverter());
  }
}

class MarkdownFileHandler extends FileHandler {
  MarkdownFileHandler() : super({'md'}) {
    lineConverters.add(RightTrimLine());
    lineConverters.add(RemoveDoubleBlankConverter());
    postConverters.add(EndsWithEOLConverter());
  }
}

class YamlFileHandler extends FileHandler {
  YamlFileHandler() : super({'yaml'}) {
    lineConverters.add(RightTrimLine());
    lineConverters.add(RemoveDoubleBlankConverter());
    postConverters.add(EndsWithEOLConverter());
  }
}
