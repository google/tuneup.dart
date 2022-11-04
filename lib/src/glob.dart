// In-lined from package:quiver.

// http://ecma-international.org/ecma-262/5.1/#sec-15.10
final _specialChars = RegExp(r'([\\\^\$\.\|\+\[\]\(\)\{\}])');

class Glob implements Pattern {
  final RegExp regex;
  final String pattern;

  Glob(this.pattern) : regex = _regexpFromGlobPattern(pattern);

  @override
  Iterable<Match> allMatches(String str, [int start = 0]) =>
      regex.allMatches(str, start);

  @override
  Match? matchAsPrefix(String string, [int start = 0]) =>
      regex.matchAsPrefix(string, start);

  bool hasMatch(String str) => regex.hasMatch(str);

  @override
  String toString() => pattern;

  @override
  int get hashCode => pattern.hashCode;

  @override
  bool operator ==(other) => other is Glob && pattern == other.pattern;
}

RegExp _regexpFromGlobPattern(String pattern) {
  var sb = StringBuffer();
  sb.write('^');
  var chars = pattern.split('');
  for (var i = 0; i < chars.length; i++) {
    var c = chars[i];
    if (_specialChars.hasMatch(c)) {
      sb.write('\\$c');
    } else if (c == '*') {
      if ((i + 1 < chars.length) && (chars[i + 1] == '*')) {
        sb.write('.*');
        i++;
      } else {
        sb.write('[^/]*');
      }
    } else if (c == '?') {
      sb.write('[^/]');
    } else {
      sb.write(c);
    }
  }
  sb.write(r'$');
  return RegExp(sb.toString());
}
