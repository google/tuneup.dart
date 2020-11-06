void main(List<String> args) {
  createOutput(loremIpsum.split(' ').take(12).join(' '));
  createOutput(loremIpsum);
}

void createOutput(String line) {
  print(line);
  warningFile('A warning.', 'tool/github.dart');
  print(line);

  group('foo group', () {
    print(line);
    print(line);
  });

  group('bar group', () {
    print(line);
    warning(line);
    print(line);
  });

  print(line);
  debug(line);
  warning(line);
  error(line);
  print(line);
  errorFile('An error.', 'tool/github.dart', line: 27);
  errorFile(
    'more errors - class Tuneup',
    'lib/tuneup.dart',
    line: 28,
    column: 7,
  );
}

void group(String name, Function callback) {
  print('::group::$name');
  callback();
  print('::endgroup::');
}

void debug(String message) {
  print('::debug::$message');
}

void warning(String message) {
  print('::warning::$message');
}

void error(String message) {
  print('::error::$message');
}

void warningFile(String message, String filePath, {int line, int column}) {
  String out = '::warning file=$filePath';
  if (line != null) {
    out += ',line=$line';
  }
  if (column != null) {
    out += ',col=$column';
  }
  out += '::$message';
  print(out);
}

void errorFile(String message, String filePath, {int line, int column}) {
  String out = '::error file=$filePath';
  if (line != null) {
    out += ',line=$line';
  }
  if (column != null) {
    out += ',col=$column';
  }
  out += '::$message';
  print(out);
}

// ::warning file={name},line={line},col={col}::{message}

// Creates a warning message and prints the message to the log. You can optionally provide a filename (file), line number (line), and column (col) number where the warning occurred.

// Example
// echo "::warning file=app.js,line=1,col=5::Missing semicolon"
// Setting an error message
// ::error file={name},line={line},col={col}::{message}

const String loremIpsum = '''
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
''';
