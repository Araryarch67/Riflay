# mimalloc 2.1.2

`mimalloc-2.1.2.tar.gz` is GitHub's source archive of mimalloc's `v2.1.2` tag
(https://github.com/microsoft/mimalloc/archive/refs/tags/v2.1.2.tar.gz, MD5
`5179c8f5cf1237d2300e2d8559a7bc55`), byte for byte. `media_kit_libs_linux`
downloads it while CMake runs and builds mimalloc into the Linux app.
`linux/CMakeLists.txt` copies this file to where the plugin looks first, so the
build doesn't depend on that download: it has no retry, and GitHub's archive
route returned 504 to CI. Replace it when the plugin moves to another mimalloc
version. MIT License, Copyright (c) 2018-2021 Microsoft Corporation, Daan Leijen
(the full text is in the archive).
