#!/bin/bash

# Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
# All rights reserved. Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# Fast fail the script on failures.
set -e

# Verify that the libraries are error free.
dart bin/tuneup.dart check

# Run the tests.
dart test/all.dart

# Install dart_coveralls; gather and send coverage data.
if [ "$REPO_TOKEN" ]; then
  export PATH="$PATH":"~/.pub-cache/bin"

  echo
  echo "Installing dart_coveralls"
  pub global activate dart_coveralls

  echo
  echo "Running code coverage report"
  # --debug for verbose logging
  pub global run dart_coveralls report \
    --token $REPO_TOKEN \
    --retry 3 \
    test/all.dart
fi
