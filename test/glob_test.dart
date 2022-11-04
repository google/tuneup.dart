import 'package:test/test.dart';
import 'package:tuneup/src/glob.dart';

// In-lined from package:quiver.

main() {
  group('Glob', () {
    test('should match "*" against sequences of word chars', () {
      expectGlob("*.html", matches: [
        "a.html",
        "_-a.html",
        r"^$*?.html",
        "()[]{}.html",
        "↭.html",
        "\u21ad.html",
        "♥.html",
        "\u2665.html"
      ], nonMatches: [
        "a.htm",
        "a.htmlx",
        "/a.html"
      ]);
      expectGlob("foo.*",
          matches: ["foo.html"],
          nonMatches: ["afoo.html", "foo/a.html", "foo.html/a"]);
    });

    test('should match "**" against paths', () {
      expectGlob("**/*.html",
          matches: ["/a.html", "a/b.html", "a/b/c.html", "a/b/c.html/d.html"],
          nonMatches: ["a.html", "a/b.html/c"]);
    });

    test('should match "?" a single word char', () {
      expectGlob("a?",
          matches: ["ab", "a?", "a↭", "a\u21ad", "a\\"],
          nonMatches: ["a", "abc"]);
    });
  });
}

expectGlob(
  String pattern, {
  required List<String> matches,
  required List<String> nonMatches,
}) {
  var glob = Glob(pattern);
  for (var str in matches) {
    expect(glob.hasMatch(str), true);
    expect(glob.allMatches(str).map((m) => m.input), [str]);
    var match = glob.matchAsPrefix(str)!;
    expect(match.start, 0);
    expect(match.end, str.length);
  }
  for (var str in nonMatches) {
    expect(glob.hasMatch(str), false);
    var m = List.from(glob.allMatches(str));
    expect(m.length, 0);
    expect(glob.matchAsPrefix(str), null);
  }
}
