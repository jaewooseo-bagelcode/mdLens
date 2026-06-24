# PLAN — mdLens × Slack 👀 인입 통합

mdLens(마크다운 뷰어)에 ① `.html` 뷰어와 ② opt-in Slack Socket Mode 리스너를 통합한다.
Slack에서 `.html`/`.md`에 **👀(:eyes:) reaction → mdLens가 파일을 받아 자기 창에 렌더**.
검증 끝난 데몬 코드(`_slack_integration/slackhtml-src/`)를 이식한다. 토큰은 **Keychain**(바이너리 임베드 0).

## Current
- [x] **`.html` 뷰어** — `readableContentTypes`에 `.html` + Info.plist(Resources/) 문서타입 추가. `DocumentView`가 `.html`은 파이프라인 우회, 실제 파일을 `loadFileURL`(base=파일 폴더). **런타임 검증 완료**(자체 CSS/JS/상대리소스 렌더).
- [x] **Slack 코드 이식** — `Sources/MarkdownViewer/Slack/{SlackAPI,SocketMode,Keychain,ManifestService,SlackConfig}`. Keychain service = bundle id 기반(dev/release 격리·프롬프트 0). AppDelegate/main/ViewerResolver 버림.
- [x] **MenuBarExtra (opt-in)** — `SlackController`(shared, 런치 시 `startIfConfigured`). 토큰 있으면 `isActive`→메뉴바 상주+Socket Mode; 없으면 메뉴바 숨김(백그라운드 0, **검증됨**). 👀→다운로드→`NSWorkspace.open(withApplicationAt: 자기번들)`로 새 문서 창.
- [x] **Setup UI** — `SlackSetupView` Window(`slack-setup`) + 앱메뉴 "Connect Slack…". 매니페스트 딥링크·토큰 2개 라이브검증·Keychain 저장·리스너 시작. **창 렌더 검증 완료**.
- [ ] **서명/공증** — `scripts/build-app.sh`(로컬, suffix 인자로 dev 격리 빌드 지원) 검증 완료. `scripts/build-release.sh`(해시주입+공증) 실행은 **커밋 후**. 릴리스 발행은 main 머지 후.
- [ ] **정리** — 이식·검증 완료 후 `~/git/markdown-viewer`·`~/git/slack-html` → `~/git/.archived` 이동 + `_slack_integration/` 삭제 (**파괴적 → 사용자 승인 대기**)

## Blocked
- (없음) — 토큰/앱/서명 인증서 모두 확보됨

## Done (압축)
- **mdLens 베이스**(이전 작업, git history 참조): DocumentGroup 전면전환 + homegrown 자동업데이터. 안정·실사용 검증.
- **Slack 데몬**(구 `~/git/slack-html`, **라이브 검증 완료** → 이식 대상):
  - Socket Mode 👀 → `files:read` 다운로드 (실토큰 라이브, MDAK 메시지로 검증)
  - 매니페스트 딥링크 자가앱생성 / Keychain 저장 / `setup` CLI
  - **서명된 .app에서 Keychain 쓰기·읽기 프롬프트 0 (OSStatus 0)** — 서명이 ACL 해결
  - ViewerResolver → mdLens 실행 검증 (통합 후엔 자기 창이라 불필요)

## 이식 가이드 (port map)
| 원본 `_slack_integration/slackhtml-src/` | mdLens 행선지 | 비고 |
|---|---|---|
| `SlackAPI.swift` | `Sources/MarkdownViewer/Slack/` | 그대로 (Sendable) |
| `SocketMode.swift` | 〃 | 그대로 (@MainActor, 자동재연결) |
| `Keychain.swift` | 〃 | service id 유지/조정 |
| `ManifestService.swift` | 〃 | 매니페스트 그대로 |
| `Config.swift` | 일부 | Keychain resolve 로직만 |
| `Setup.swift` | → SwiftUI "Connect Slack" 뷰 | CLI→UI 각색 |
| `AppDelegate/main/ViewerResolver` | **버림** | mdLens 앱 생명주기/MenuBarExtra로 대체, 자기 창에 직접 엶 |

## Decisions
| 항목 | 결정 | 이유 |
|------|------|------|
| 통합 | 데몬을 mdLens로 흡수, **단일 앱** | 토큰=Keychain이라 배포 누출 0 → 두 앱 유지 이유 소멸 |
| opt-in | Slack 미설정 시 기존 뷰어 그대로(상주 0) | 순수 뷰어 사용자 영향 0 |
| 이벤트 | per-user **BYO-app + Socket Mode** | 즉시성·무서버. 공유앱 Socket Mode는 로드밸런싱으로 불가 |
| 토큰 | **Keychain** (임베드 폐기) | 동료 배포형 → 바이너리에 비밀 0 |
| 서명 | `Developer ID Application: Sugarscone (5FK7UUGMX3)` | Keychain ACL 안정 + Gatekeeper. 기존 mdLens 인프라 |
| 뷰어 핸드오프 | 없음(자기 창에 직접) | mdLens가 곧 뷰어 |
| 매니페스트 | `user_events: reaction_added` + user scopes + socket_mode | user-token만으로 동작(봇 불필요·봇초대 불요) |
| Keychain service | `Bundle.main.bundleIdentifier` 기반(하드코딩 폐기) | dev(`…mdlens.dev`)·release 토큰 격리 + 자기앱이 생성·읽기 → ACL 프롬프트 0 보장 |
| dev 빌드 격리 | `build-app.sh <suffix>` → `mdLens-<suffix>.app`/`…mdlens.<suffix>` | 설치된 release와 bundle id 충돌(이중 인스턴스) 방지 |

## ⚠️ Gotchas (반드시 숙지)
- **`pkill -f <패턴>` 절대 금지** — 실행 셸(`sh -c "...pkill -f X..."`)의 명령줄에 패턴이 들어가 **자기 셸을 죽임**(맥락 끊김의 원인이었음). 프로세스 정리는 **기록한 정확한 PID만** `kill "$(cat ….pid)"`.
- Keychain ACL은 **서명된 바이너리**라야 프롬프트 없이 됨(unsigned = OSStatus **-128**). 개발 중 setup·앱 모두 서명본으로 테스트.
- `AGENTS.md` 규칙: `main` 보호, **`dev`에서 작업·PR로 머지**, 파괴적 git은 사용자 승인.
- 토큰은 채팅에 평문 노출됐었음 → 배포 전 한 번 **회전(reinstall)** 권장.
