#!/bin/bash
# Runs the ConversionKit suite.
#
# The suite is a plain executable rather than a SwiftPM test target: XCTest
# ships only with a full Xcode, and the Testing.framework bundled with the
# Command Line Tools links against a lib_TestingInterop.dylib that Apple does
# not ship. See Tests/ConversionKitTests/TestRunner.swift.
set -euo pipefail
cd "$(dirname "$0")"

exec swift run -c release ConversionKitTests "$@"
