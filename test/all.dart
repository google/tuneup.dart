// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library tuneup.all_tests;

import 'common_test.dart' as common_test;
import 'integration_test.dart' as integration_test;

void main() {
  common_test.defineTests();
  integration_test.defineTests();
}
