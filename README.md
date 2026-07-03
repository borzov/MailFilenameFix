# MailFilenameFix

A Mail.app extension for macOS that fixes garbled attachment filenames like:

```
utf-8''%D0%93%D1%80%D0%B0%D1%84%D0%B8%D0%BA%D0%B0-2.png   →   Графика-2.png
```

## The problem

Apple Mail on macOS (unlike iOS Mail and every webmail) does not decode
RFC 2231/5987 extended parameters (`filename*=utf-8''%...`) in
`Content-Disposition` / `Content-Type` headers. Attachments with non-ASCII
(e.g. Cyrillic) names sent by servers that use this — perfectly valid —
encoding show up as raw percent-encoded garbage. Long names can't even be
saved to disk because the encoded form exceeds the 255-byte filename limit.
The bug has been reported since macOS 11 and is still present in macOS 26.

## How it works

MailKit (the only extension API left since macOS Sonoma removed legacy
plug-ins) offers no direct hook for attachment names. This project uses the
**Message Security Extension** entry point instead: Mail hands the raw RFC822
message to `decodedMessage(forMessageData:)`, and the extension returns a copy
where extended `filename*=` / `name*=` parameters are rewritten into the
RFC 2047 encoded-word form (`filename="=?utf-8?B?...?="`) that Mail renders
correctly — the same form Gmail and Outlook produce.

- Display-time only: messages on the IMAP server are never modified.
- Byte-surgical: only affected header lines change.
- Any source charset (utf-8, windows-1251, koi8-r, … via IANA lookup),
  `filename*0*`/`filename*1*` continuations supported.
- Cryptographically signed messages (`multipart/signed`) are left untouched.
- Messages that need no fix are passed through with a fast `nil` return.

## Build

Requires Xcode and [xcodegen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). Set your own development team in `project.yml`,
then:

```sh
xcodegen generate
xcodebuild -project MailFilenameFix.xcodeproj -scheme MailFilenameFix \
    -configuration Release build
```

Copy the built `MailFilenameFix.app` to `/Applications`, launch it once,
then enable the extension in **Mail → Settings → Extensions** and restart
Mail.

## Tests

The header-rewriting core (`Extension/FilenameFixer.swift`) has a standalone
test suite:

```sh
swiftc -o /tmp/fixer_test Extension/FilenameFixer.swift tests/main.swift
/tmp/fixer_test
```

## License

MIT
