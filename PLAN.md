# PLAN — mdLens × Slack 👀 인입 통합

mdLens(마크다운 뷰어)에 ① `.html` 뷰어와 ② opt-in Slack Socket Mode 리스너를 통합한다.
Slack에서 `.html`/`.md`에 **👀(:eyes:) reaction → mdLens가 파일을 받아 자기 창에 렌더**.
검증 끝난 데몬 코드(`_slack_integration/slackhtml-src/`)를 이식한다. 토큰은 **Keychain**(바이너리 임베드 0).

## Current
- [ ] **QL 풀-렌더 시각 확인 (사용자 수동, 1스텝)** — Finder에서 `.md` 선택→스페이스바. highlight.js 색·표·체크박스까지 보이면 OK. (구현·서명·임베드·JS실행 검증은 끝, 최종 리치 렌더 스크린샷만 화면 잠금으로 미캡처)
- [ ] **라이브 Slack 검증 (사용자 수동)** — 앱메뉴 "Connect Slack…" → 매니페스트 앱 생성 → xapp-/xoxp- 입력 → 메뉴바 👀 → Slack `.html`/`.md`에 👀 → 창 열림. (실토큰 필요 → 대행 불가)
- [ ] **릴리스 발행 (선택)** — QL 포함 새 빌드로 `build-release.sh` 재실행 후 `gh release create build-<hash> … /tmp/mdLens-build-<hash>-arm64.zip`. (이전 `build-10693c2`는 QL 미포함)

## Blocked
- (없음) — 토큰/앱/서명 인증서 모두 확보됨

## Done (압축)
Phase 1-6 완료 (커밋 7dea980 `.html` 뷰어, 10693c2 Slack 통합 → main):
- **`.html` 뷰어**: `loadFileURL` 직접 로드(파이프라인 우회). 런타임 검증.
- **Slack 이식**: `Sources/MarkdownViewer/Slack/{SlackAPI,SocketMode,Keychain,ManifestService,SlackConfig}`. AppDelegate/main/ViewerResolver는 `SlackController`/`SlackSetupView`로 재구현.
- **MenuBarExtra opt-in**: `SlackController.shared` 런치 시 `startIfConfigured`. 미설정=메뉴바 숨김(백그라운드 0, 검증). 👀→다운로드→자기 번들로 새 창.
- **Setup UI**: `SlackSetupView` Window + 앱메뉴 진입. 라이브검증·Keychain 저장. 창 렌더 검증.
- **서명/공증**: `build-release.sh` → 공증 **Accepted** + 스테이플 (`build-10693c2`, `spctl` Notarized). `build-app.sh <suffix>`로 dev 격리 빌드.
- **정리**: 구 `markdown-viewer`·`slack-html` → `~/git/.archived/`, `_slack_integration/` 삭제.
- **베이스**(이전): DocumentGroup 전환 + 자동업데이터. 상세는 git history.
- **Quick Look 확장**(커밋 8dbc327): `.md`/`.html` Finder 미리보기. `MarkdownCore` 공유 모듈 분리 후 `mdLensQL.appex`가 WKWebView+MarkdownRenderer로 풀 충실도 렌더. **핵심 발견: QL 확장 WKWebView에서 JS 실행됨**(최소 3 entitlement 한정; JIT/lib entitlement 추가 시 깨짐). PR #1의 NSTextView 우회 폐기.

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
