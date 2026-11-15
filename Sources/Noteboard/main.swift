import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 메뉴바에만 상주한다(Dock 아이콘 없음). 번들의 LSUIElement 와 같은 뜻.
app.setActivationPolicy(.accessory)
app.run()
