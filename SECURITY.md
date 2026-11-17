# Security Policy

## Supported versions

Only the latest release gets security fixes. Update through the app (Settings › About), Scoop, Homebrew, or the
[releases page](https://github.com/Araryarch67/Riflay/releases/latest).

| Version | Supported |
|---|---|
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

Please **don't open a public issue** for a security problem.

Report it privately through GitHub:
[Security › Report a vulnerability](https://github.com/Araryarch67/Riflay/security/advisories/new).

Include what you can of:

- What the problem is and what an attacker could do with it
- The platform (Windows, macOS, Linux, Android, iOS) and Riflay version
- Steps to reproduce, or a proof of concept
- Any idea of a fix

You can expect a first answer within a week. Once a fix is released, the advisory is published and you're credited
unless you'd rather not be.

## Scope

In scope: the Riflay app and its release builds, its update checks, the local servers it runs (Listen together, the
command-line bridge, the audio proxy), and how it stores sign-ins and settings.

Out of scope: the services Riflay talks to (YouTube Music, Monochrome, SoundCloud, Spotify, Last.fm, Discord…),
which should be reported to them directly, and issues needing an already compromised device.
