#!/usr/bin/env bash
# Sourced by other scripts. Selects a toolchain that includes XCTest.
#
# The Command Line Tools ship Swift but not XCTest, so if xcode-select points at them and
# Xcode is installed, use Xcode for this process only. Nothing system-wide is changed.

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    active="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$active" == *CommandLineTools* && -d /Applications/Xcode.app/Contents/Developer ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
fi
