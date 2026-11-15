# SpotiFLAC extension runtime

Go backend sources (excluding upstream tests), with the Riflay adapters below, from
https://github.com/giturass/SpotiFLAC at
`fe722862735f475b30e9736a65dba2a007056b1e` (MIT; see LICENSE).

`riflay_bridge.go` is Riflay's small exported adapter for the upstream provider
wrapper. The JavaScript interpreter, host APIs, permissions, manifest validation,
package installation, settings, authentication and repository implementation are
the upstream implementation, rather than an emulation of the extension API.

Riflay runs this runtime in a separate bundled process using JSON over stdin/stdout.
No local TCP server is exposed. `riflay_ffmpeg.go` and one hook in
`extension_runtime_ffmpeg.go` replace the mobile FFmpeg queue with a native runner:
arguments are parsed without a shell, file paths use the upstream sandbox, and
unsupported FFmpeg flags/network inputs fail explicitly. Extension data lives under Riflay's private support
directory and is not included in Riflay backups.
