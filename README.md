# noteboard

맥 전용 퀵노트 앱. 어디서든 `⌥⇧N` 을 누르면 작은 노트 창이 새로 뜨고, 쓰는 즉시 내 맥의 폴더에 파일로 저장된다.

## 기능

- **단축키로 새 창**: `⌥⇧N` 을 누를 때마다 새 창. 마우스가 있는 화면 가운데에 화면 가로·세로 1/4 크기로 뜨고, 여러 개면 계단식으로 비켜 선다. 창 크기를 바꾸면 다음 창부터 그 크기로 뜬다.
- **편집기**: 어두운 배경, 왼쪽 줄 번호(자동 줄바꿈돼도 한 줄로 센다), 현재 줄 강조.
- **마크다운 / 텍스트**: 노트마다 바꿀 수 있다(`⇧⌘M`). 마크다운은 쓰면서 바로 꾸밈이 보이고 기호는 흐리게 남는다. `⇧⌘P` 로 미리보기. 목록에서 Enter 를 치면 다음 줄에 기호가 붙고, Tab / ⇧Tab 으로 들여쓴다.
- **사이드바**(`⌃⌘S`): 단축키로 연 창에서는 닫혀 있다. 열면 창이 왼쪽으로 220pt 넓어진다. 제목(없으면 첫 줄)과 날짜가 보이고, 제목·날짜·내용으로 검색한다(`⇧⌘F`). 두 번 누르면 제목을 바꾼다.
- **항상 위에**: 창마다 켜고 끈다(`⇧⌘T`). 새 창의 기본값은 설정에서.
- **닫기**: `⌘W` 또는 `Esc`. 한글 조합 중의 Esc 는 조합만 끝내고, 검색어가 있으면 먼저 검색어를 지운다.
- **메뉴바 아이콘**: Dock 아이콘 없이 메뉴바에 상주한다. 로그인할 때 자동 실행(응용 프로그램 폴더에서 처음 실행할 때 켜진다).
- **업데이트**: Sparkle. 새 버전이 있으면 메뉴바 아이콘에 점이 찍히고 메뉴에 "새 버전 설치…" 가 뜬다.
- **설정**: 저장 폴더, 로그인 시 자동 실행, 새 노트 기본 포맷, 글자 크기, 항상 위에 기본값, 단축키 4개, 업데이트 자동 확인.

## 저장 방식

노트 하나 = 파일 하나. 기본 폴더는 `~/Documents/noteboard` 이고 설정에서 바꿀 수 있다(바꿀 때 기존 노트를 옮길지 묻는다).

- **파일 이름 = 제목, 확장자 = 포맷**(`.md` / `.txt`), **날짜 = 파일의 생성·수정 시각**. 파일 안에 따로 적는 정보는 없다.
- 제목이 없는 노트는 `Untitled-20261116-143205.md` 처럼 저장하고, 목록에는 첫 줄을 보여 준다.
- 입력이 멈추고 0.5초 뒤 자동 저장한다. 아무것도 안 쓴 노트는 닫을 때 지운다. 삭제는 휴지통으로 보낸다.
- 다른 편집기에서 파일을 고치면 열린 창에 바로 반영된다(그 창에서 고치는 중이 아닐 때).

## 개발

macOS 15 이상, Xcode 16 이상(Swift 6 툴체인).

```bash
swift build
swift test                 # 화면과 무관한 로직(NoteboardCore) 시험
scripts/selftest.sh        # 실제 창으로 저장·제목 변경·포맷 전환·외부 수정·빈 노트 삭제·휴지통 흐름 시험
scripts/snapshots.sh       # 창을 화면 밖에 그려 build/snapshots/*.png 로 저장(디자인 비교용)
scripts/bundle.sh          # 서명된 build/Noteboard.app (NOTARIZE=1 이면 공증 + build/Noteboard.zip)
```

구조:

- `Sources/NoteboardCore` — 파일 이름 규칙, 저장 폴더, 날짜 표시, 검색, 마크다운 꾸밈·미리보기 HTML, 목록 이어 쓰기, 창 크기 계산, 단축키 표기.
- `Sources/Noteboard` — AppKit 앱. 창(`NoteWindowController`), 편집기(`EditorTextView`, `LineNumberRulerView`, `MarkdownStyler`), 사이드바, 메뉴바, 설정(SwiftUI), 전역 단축키(Carbon), Sparkle.

## 배포

코드 레포는 비공개라 앱이 로그인 없이 업데이트를 받을 수 없다. 그래서 zip 과 `appcast.xml` 은 **공개 릴리스 레포**(`jikwon-labs/Noteboard-releases`)에 올리고, 앱은 그 레포의 최신 릴리스에 붙은 `appcast.xml` 을 본다.

처음 한 번:

```bash
gh repo create jikwon-labs/Noteboard-releases --public --description "noteboard 릴리스"
scripts/sparkle-keys.sh    # 업데이트 서명 키(비밀 키는 키체인, 공개 키는 Resources/SparklePublicKey.txt)
git add Resources/SparklePublicKey.txt && git commit -m "chore: Sparkle 공개 키" && git push
```

배포할 때마다:

```bash
scripts/release.sh 1.0.0             # 시험 → 서명·공증 → appcast 서명 → 커밋·태그·push → 릴리스
DRY_RUN=1 scripts/release.sh 1.0.0   # 커밋·push·릴리스 없이 build/ 까지만
```

공증 계정은 `xcrun notarytool store-credentials` 로 저장한 프로필을 쓴다(기본 `symboard-notary`, `NOTARY_PROFILE` 로 바꿀 수 있다).
Sparkle 비밀 키를 잃어버리면 기존 설치본에 업데이트를 보낼 수 없으니 `generate_keys -x` 로 백업해 둔다.
