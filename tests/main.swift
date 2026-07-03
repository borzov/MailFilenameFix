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

print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
