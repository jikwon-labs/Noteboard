# noteboard

맥 전용 퀵노트 앱(Swift 6 툴체인, SwiftPM). `⌥⇧N` 으로 새 노트 창, 노트 하나 = 파일 하나. 자세한 기능과 저장 규칙은 README.

## 빌드와 검증

- `swift build`, `swift test` — 보고 전에 항상 `swift test` 와 `scripts/selftest.sh` 를 돌린다.
- 화면을 바꿨으면 `scripts/snapshots.sh` 로 PNG 를 뽑아 확인한다(창을 화면 밖에 그린다, 사용자 화면에 뜨지 않음).
- `scripts/bundle.sh` — 서명된 `build/Noteboard.app`. 앱을 직접 띄워 볼 때는 `-storageFolder <임시 폴더>` 를 붙여 사용자의 실제 노트 폴더를 건드리지 않는다.

## 구조

- `NoteboardCore` — 화면과 무관한 로직. 테스트(`Tests/NoteboardCoreTests`)는 이 타깃만 본다.
- `Noteboard` — AppKit 앱(Swift 5 언어 모드). 설정 창만 SwiftUI. 편집기는 TextKit 1(줄 번호가 줄 조각 단위라서).

## 규칙

- **버전**: `Sources/NoteboardCore/Version.swift` 한 곳에만 둔다. 배포는 사용자가 `scripts/release.sh <버전>` 으로 직접 한다. Claude 는 `DRY_RUN=1` 로만 돌린다.
- **업데이트 주소**: 레포가 비공개라 appcast 는 main 의 `appcast.xml`(raw 주소), zip 은 이 레포의 릴리스 첨부 파일이고, 앱은 `gh auth token` 으로 읽은 토큰을 붙여 받는다. `SUFeedURL` 이나 `appcast.xml` 위치를 바꾸면 이미 설치된 앱이 업데이트를 못 찾으니 바꾸지 않는다. 토큰을 앱이나 레포에 넣지 않는다.
- **편집기 꾸밈**: `MarkdownStyler` 는 `didProcessEditing` 안에서 글꼴을 다시 칠하므로 끝에 `fixAttributes` 를 꼭 부른다(안 하면 한글이 안 보인다). `typingAttributes` 는 편집 처리 중에 바꾸지 않는다(글이 비면 AppKit 이 예외를 던진다).
- **커밋 메시지**: `feat:` `fix:` `perf:` `chore:` `docs:` 머리말 뒤에 한국어 쉬운 말.
- `PLAN*.md` `REPORT*.md` 는 git 에 넣지 않는 로컬 문서다.
