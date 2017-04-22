// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'analysis_lib_test.dart' as analysis_lib_test;
import 'common_test.dart' as common_test;
import 'integration_test.dart' as integration_test;

void main() {
  analysis_lib_test.defineTests();
  common_test.defineTests();
  integration_test.defineTests();
}
