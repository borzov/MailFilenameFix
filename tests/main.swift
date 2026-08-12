import Foundation

func msg(_ headers: String) -> Data {
    let raw = "From: a@b\r\nMIME-Version: 1.0\r\n" + headers + "\r\nbody\r\n"
    return raw.data(using: .isoLatin1)!
}

var failures = 0
func check(_ label: String, _ cond: Bool) {
    print((cond ? "PASS " : "FAIL ") + label)
    if !cond { failures += 1 }
}

// 1. simple utf-8 extended param + other params preserved
let simple = msg(
    "Content-Type: image/png;\r\n" +
    " name*=utf-8''%D0%93%D1%80%D0%B0%D1%84%D0%B8%D0%BA%D0%B0%2D2.png\r\n" +
    "Content-Disposition: attachment;\r\n" +
    " filename*=utf-8''%D0%93%D1%80%D0%B0%D1%84%D0%B8%D0%BA%D0%B0%2D2.png;\r\n" +
    " size=1234\r\n" +
    "Content-Transfer-Encoding: base64\r\n")
if let out = FilenameFixer.fix(simple), let s = String(data: out, encoding: .isoLatin1) {
    let expectB64 = Data("Графика-2.png".utf8).base64EncodedString()
    check("simple: filename encoded", s.contains("filename=\"=?utf-8?B?\(expectB64)?=\""))
    check("simple: name encoded too", s.contains("name=\"=?utf-8?B?\(expectB64)?=\""))
    check("simple: size kept", s.contains("size=\"1234\""))
    check("simple: body intact", s.hasSuffix("\r\nbody\r\n"))
    check("simple: other headers intact", s.contains("Content-Transfer-Encoding: base64"))
    check("simple: idempotent", FilenameFixer.fix(out) == nil)
} else { check("simple: changed", false) }

// 2. continuations filename*0*/filename*1*
let cont = msg(
    "Content-Disposition: attachment;\r\n" +
    " filename*0*=utf-8''%D0%A2%D0%97%20%D0%A0%D0%B5%D0%B3;\r\n" +
    " filename*1*=%D0%B8%D1%81%D1%82%D1%80%D0%B0%D1%86%D0%B8%D1%8F.docx\r\n")
if let out = FilenameFixer.fix(cont), let s = String(data: out, encoding: .isoLatin1) {
    let expect = Data("ТЗ Регистрация.docx".utf8).base64EncodedString()
    check("continuation: merged", s.contains("=?utf-8?B?\(expect)?="))
} else { check("continuation: changed", false) }

// 3. windows-1251
let cp = msg("Content-Disposition: attachment; filename*=windows-1251''%CF%F0%E8%E2%E5%F2.txt\r\n")
if let out = FilenameFixer.fix(cp), let s = String(data: out, encoding: .isoLatin1) {
    let expect = Data("Привет.txt".utf8).base64EncodedString()
    check("cp1251: decoded", s.contains("=?utf-8?B?\(expect)?="))
} else { check("cp1251: changed", false) }

// 4. plain message untouched
let clean = msg("Content-Disposition: attachment; filename=\"report.pdf\"\r\n")
check("clean: untouched", FilenameFixer.fix(clean) == nil)

// 5. signed mail untouched
let signed = msg(
    "Content-Type: multipart/signed; boundary=\"b\"\r\n" +
    "Content-Disposition: attachment; filename*=utf-8''%D0%90.png\r\n")
check("signed: untouched", FilenameFixer.fix(signed) == nil)

// 6. ascii-only extended param -> plain quoted filename
let ascii = msg("Content-Disposition: attachment; filename*=utf-8''report%202.pdf\r\n")
if let out = FilenameFixer.fix(ascii), let s = String(data: out, encoding: .isoLatin1) {
    check("ascii: plain quoted", s.contains("filename=\"report 2.pdf\""))
} else { check("ascii: changed", false) }

// MARK: - mojibake repair

/// UTF-8 bytes of `s` reinterpreted as Latin-1 — exactly what a mail client
/// shows when it renders raw UTF-8 header bytes as a single-byte charset.
func mojibake(_ s: String) -> String {
    String(data: Data(s.utf8), encoding: .isoLatin1)!
}

func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString() }

func qEncode(_ s: String) -> String {
    Data(s.utf8).map { String(format: "=%02X", $0) }.joined()
}

let goodName = "изображение.png"
let goodB64 = b64(goodName)

// 7. MojibakeRepair in isolation
check("repair: utf-8 read as latin-1", MojibakeRepair.repair(mojibake(goodName)) == goodName)
check("repair: double mojibake", MojibakeRepair.repair(mojibake(mojibake(goodName))) == goodName)
check("repair: plain ascii untouched", MojibakeRepair.repair("report.pdf") == nil)
check("repair: correct cyrillic untouched", MojibakeRepair.repair(goodName) == nil)
check("repair: latin-1 name untouched", MojibakeRepair.repair("Résumé.pdf") == nil)
check("repair: german name untouched", MojibakeRepair.repair("Grüße.pdf") == nil)
check("repair: cp1251-as-latin1 untouched", MojibakeRepair.repair("èçîáðàæåíèå.png") == nil)
check("repair: empty untouched", MojibakeRepair.repair("") == nil)

// 8. form A — raw UTF-8 bytes in an unencoded filename parameter
let rawBytes = msg(
    "Content-Type: image/png; name=\"\(mojibake(goodName))\"\r\n" +
    "Content-Disposition: attachment; filename=\"\(mojibake(goodName))\"\r\n")
if let out = FilenameFixer.fix(rawBytes), let s = String(data: out, encoding: .isoLatin1) {
    check("raw: filename encoded", s.contains("filename=\"=?utf-8?B?\(goodB64)?=\""))
    check("raw: name encoded", s.contains("name=\"=?utf-8?B?\(goodB64)?=\""))
    check("raw: idempotent", FilenameFixer.fix(out) == nil)
} else { check("raw: changed", false) }

// 9. form B — encoded-word that correctly carries already-broken text
let doubleEncoded = msg(
    "Content-Disposition: attachment; filename=\"=?utf-8?B?\(b64(mojibake(goodName)))?=\"\r\n")
if let out = FilenameFixer.fix(doubleEncoded), let s = String(data: out, encoding: .isoLatin1) {
    check("double: repaired", s.contains("filename=\"=?utf-8?B?\(goodB64)?=\""))
} else { check("double: changed", false) }

// 10. form C — charset lies: says iso-8859-1, carries UTF-8
let liedCharset = msg(
    "Content-Disposition: attachment; filename=\"=?iso-8859-1?Q?\(qEncode(goodName))?=\"\r\n")
if let out = FilenameFixer.fix(liedCharset), let s = String(data: out, encoding: .isoLatin1) {
    check("lied charset: repaired", s.contains("filename=\"=?utf-8?B?\(goodB64)?=\""))
} else { check("lied charset: changed", false) }

// 11. form C via RFC 2231 — extended param whose charset lies
let liedExtended = msg(
    "Content-Disposition: attachment;\r\n" +
    " filename*=iso-8859-1''%D0%B8%D0%B7%D0%BE%D0%B1%D1%80%D0%B0%D0%B6%D0%B5%D0%BD%D0%B8%D0%B5.png\r\n")
if let out = FilenameFixer.fix(liedExtended), let s = String(data: out, encoding: .isoLatin1) {
    check("lied extended: repaired", s.contains("filename=\"=?utf-8?B?\(goodB64)?=\""))
} else { check("lied extended: changed", false) }

// 12. correct names must never be touched
let correctWord = msg(
    "Content-Disposition: attachment; filename=\"=?utf-8?B?\(goodB64)?=\"\r\n")
check("correct encoded-word: untouched", FilenameFixer.fix(correctWord) == nil)

let correctCP = msg(
    "Content-Disposition: attachment; filename=\"=?windows-1251?B?\(Data("Привет.txt".data(using: .windowsCP1251)!).base64EncodedString())?=\"\r\n")
check("correct cp1251 word: untouched", FilenameFixer.fix(correctCP) == nil)

let latin1Name = msg(
    "Content-Disposition: attachment; filename=\"R\u{e9}sum\u{e9}.pdf\"\r\n")
check("latin-1 raw name: untouched", FilenameFixer.fix(latin1Name) == nil)

let cp1251Raw = msg(
    "Content-Disposition: attachment; filename=\"\u{e8}\u{e7}\u{ee}\u{e1}\u{f0}\u{e0}\u{e6}\u{e5}\u{ed}\u{e8}\u{e5}.png\"\r\n")
check("cp1251 raw name: untouched", FilenameFixer.fix(cp1251Raw) == nil)

// 13. broken name inside a signed message stays broken (signature wins)
let signedBroken = msg(
    "Content-Type: multipart/signed; boundary=\"b\"\r\n" +
    "Content-Disposition: attachment; filename=\"\(mojibake(goodName))\"\r\n")
check("signed broken: untouched", FilenameFixer.fix(signedBroken) == nil)

// 14. body bytes survive a header repair untouched
if let out = FilenameFixer.fix(rawBytes), let s = String(data: out, encoding: .isoLatin1) {
    check("raw: body intact", s.hasSuffix("\r\nbody\r\n"))
    check("raw: From header intact", s.contains("From: a@b\r\n"))
} else { check("raw: body check ran", false) }

print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
