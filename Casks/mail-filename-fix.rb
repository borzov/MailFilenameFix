cask "mail-filename-fix" do
  version "1.0.0"
  sha256 "32ca1137ae58e14c3c34fac8f014568120ec743c03979652a400cca9e9fab5df"

  url "https://github.com/borzov/MailFilenameFix/releases/download/v#{version}/MailFilenameFix-#{version}.zip"
  name "Mail Filename Fix"
  desc "Mail.app extension that fixes RFC 2231-encoded attachment filenames"
  homepage "https://github.com/borzov/MailFilenameFix"

  depends_on macos: :ventura

  app "Mail Filename Fix.app"

  # The app is not signed with a Developer ID (no notarization), so after
  # installation it is stripped of quarantine and re-signed with a local
  # ad-hoc signature — Gatekeeper then treats it like a locally built app.
  # The re-sign logic ships inside the bundle (Contents/Resources/resign.sh),
  # so it always matches the installed version.
  postflight do
    app_path = "#{appdir}/Mail Filename Fix.app"
    system_command "/bin/bash",
                   args: ["#{app_path}/Contents/Resources/resign.sh", app_path]
  end

  uninstall quit: "com.borzov.MailFilenameFix"

  zap trash: [
    "~/Library/Containers/com.borzov.MailFilenameFix",
    "~/Library/Containers/com.borzov.MailFilenameFix.FilenameFixExtension",
  ]

  caveats <<~EOS
    Включите расширение: Почта → Настройки → Расширения → Filename Fix,
    затем перезапустите Почту.
  EOS
end
