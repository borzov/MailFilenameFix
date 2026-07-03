import SwiftUI

@main
struct MailFilenameFixApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mail Filename Fix")
                    .font(.title2).bold()
                Text("""
                Это приложение-контейнер для расширения Mail, которое исправляет \
                искажённые (RFC 2231) имена вложений — «utf-8''%D0%93…» → «Графика.png».

                Включение:
                1. Откройте Почта → Настройки → Расширения.
                2. Включите «Filename Fix».
                3. Перезапустите Почту.

                Приложение должно оставаться в папке «Программы».
                """)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(width: 460)
        }
        .windowResizability(.contentSize)
    }
}
