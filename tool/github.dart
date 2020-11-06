void main(List<String> args) {
  createOutput(loremIpsum.split(' ').take(12).join(' '));
  createOutput(loremIpsum);
}

void createOutput(String line) {
  print(line);
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

const String loremIpsum = '''
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
''';
