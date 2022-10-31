
# zig-archive

[![Linux Workflow Status](https://img.shields.io/github/workflow/status/truemedian/zig-archive/Linux?label=Linux&style=for-the-badge)](https://github.com/truemedian/zig-archive/actions/workflows/linux.yml)
[![Windows Workflow Status](https://img.shields.io/github/workflow/status/truemedian/zig-archive/Windows?label=Windows&style=for-the-badge)](https://github.com/truemedian/zig-archive/actions/workflows/windows.yml)
[![MacOS Workflow Status](https://img.shields.io/github/workflow/status/truemedian/zig-archive/MacOS?label=MacOS&style=for-the-badge)](https://github.com/truemedian/zig-archive/actions/workflows/macos.yml)

Reading and writing archives in zig.

## Features

- Reading and writing zip archives
  - Supports zip64
  - Supports zip files with a preamble (like self-extracting archives)
- TODO: Reading and writing tar archives

## Examples

Reading (and extracting) a zip archive: tests/read_zip.zig

Writing a zip archive: tests/write_zip.zig
