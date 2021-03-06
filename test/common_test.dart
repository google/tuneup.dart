// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:tuneup/src/common.dart';

void main() => defineTests();

void defineTests() {
  group('common', () {
    test('pluralize', () {
      expect(pluralize('cat', 0), 'cats');
      expect(pluralize('cat', 1), 'cat');
      expect(pluralize('cat', 2), 'cats');
    });

    test('format', () {
      expect(formatNumber(0), '0');
      expect(formatNumber(10), '10');
      expect(formatNumber(100), '100');
      expect(formatNumber(1000), '1,000');
      expect(formatNumber(10000), '10,000');
      expect(formatNumber(100000), '100,000');
      expect(formatNumber(1000000), '1,000,000');
    });
  });
}
