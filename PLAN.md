# PLAN — mdLens × Slack 👀 인입 통합

mdLens(마크다운 뷰어)에 ① `.html` 뷰어와 ② opt-in Slack Socket Mode 리스너를 통합한다.
Slack에서 `.html`/`.md`에 **👀(:eyes:) reaction → mdLens가 파일을 받아 자기 창에 렌더**.
검증 끝난 데몬 코드(`_slack_integration/slackhtml-src/`)를 이식한다. 토큰은 **Keychain**(바이너리 임베드 0).

## Current
- [ ] **Slack 👀 = "내 반응"만 트리거** — 현재 `user_events: reaction_added`가 **남의 반응까지** 전달해서, 다른 사람이 👀 달면 내 mdLens가 열림. 포팅 때 구 데몬의 `onlyMyReactions`/`myUserID` 필터를 드롭한 회귀. **수정**: `SlackController.start()`가 `authTestUserID()` 결과(내 user_id)를 프로퍼티에 저장 → `handle()`에 `guard r.user == myUserID else { return }` 추가. (`SocketModeClient.Reaction.user` 이미 존재). 완료기준: 남이 👀 → 무동작, 내가 👀 → 열림. 검증 후 `build-release`.

## Blocked
- [ ] **issue #2 — macOS 26.4에서 문서 창 0개** (신고자 sungmopark). **26.5(메인테이너)에선 재현 불가**(MenuBarExtra 강제활성·full-configured 두 PoC 모두 창 정상). 신고자 26.4 검증(2026-06-27): **MenuBarExtra 원인 아님**(Disconnect로 제거해도 open/File→New 둘 다 0개) · 환경(saved-state·번들중복·윈도우매니저·translocation) 전부 배제 · Console에 `LSExceptions timeout`/`task name port right 실패(0x5)`, WebKit web content는 뜨는데 **document scene(NSWindow) 미생성**. → 용의자 = `Window("Connect Slack")` scene 또는 **순수 26.4 DocumentGroup 회귀**. **대기: Director가 26.5 업데이트 후 결과 공유 예정**(풀리면 OS 버그 확정 → 워크어라운드=OS 업데이트, 26.4 잔류자 위해 scene 최소화 빌드 검토). blind fix 금지(MenuBarExtra 헛다리 전례).

## Backlog
- **코드블록 CJK 정렬 — 폰트 무의존화**: 현재 **Sarasa Term**(ambiguous-width=1셀) 설치자만 완전 정렬됨(`pre code` 폰트스택, `build-01e533d`). 미설치 동료는 D2Coding 폴백→ambiguous 드리프트. 모든 머신 보장하려면 Sarasa Term류 webfont(CDN) 로드 추가.

## Done (압축)
Phase 1-6 완료 (커밋 7dea980 `.html` 뷰어, 10693c2 Slack 통합 → main):
- **`.html` 뷰어**: `loadFileURL` 직접 로드(파이프라인 우회). 런타임 검증.
- **Slack 이식**: `Sources/MarkdownViewer/Slack/{SlackAPI,SocketMode,Keychain,ManifestService,SlackConfig}`. AppDelegate/main/ViewerResolver는 `SlackController`/`SlackSetupView`로 재구현.
- **MenuBarExtra opt-in**: `SlackController.shared` 런치 시 `startIfConfigured`. 미설정=메뉴바 숨김(백그라운드 0, 검증). 👀→다운로드→자기 번들로 새 창.
- **Setup UI**: `SlackSetupView` Window + 앱메뉴 진입. 라이브검증·Keychain 저장. 창 렌더 검증.
- **서명/공증**: `build-release.sh` → 공증 **Accepted** + 스테이플 (`build-10693c2`, `spctl` Notarized). `build-app.sh <suffix>`로 dev 격리 빌드.
- **정리**: 구 `markdown-viewer`·`slack-html` → `~/git/.archived/`, `_slack_integration/` 삭제.
- **베이스**(이전): DocumentGroup 전환 + 자동업데이터. 상세는 git history.
- **Quick Look 확장**(커밋 8dbc327): `.md`/`.html` Finder 미리보기. `MarkdownCore` 공유 모듈 분리 후 `mdLensQL.appex`가 WKWebView+MarkdownRenderer로 풀 충실도 렌더. **핵심 발견: QL 확장 WKWebView에서 JS 실행됨**(최소 3 entitlement 한정; JIT/lib entitlement 추가 시 깨짐). PR #1의 NSTextView 우회 폐기. 사용자 시각 확인 완료.
- **리뷰·하드닝**(6ba58b5, d4b2d87): verify×2 + codex×2 → SocketMode stop 취소·다운로드 25MB 캡·QL temp 정리·build-release 자기완결. Critical/High 0으로 수렴.
- **Slack 앱 이름 유니크**(e3a2834): 매니페스트 `name`을 `mdLens (<로그인명>-<랜덤4hex>)`로(BYO-app 충돌 방지, 1회 생성·UserDefaults 고정).
- **릴리스·배포**: `build-e3a2834` 공증+발행(latest), `/Applications` 설치(QL 등록), 로컬 자동업데이트 체크 = 최신 일치(무동작) 검증. commitHash 박힘도 Updater 행동으로 직접 확인.
- **라이브 Slack 검증 완료**: 실토큰으로 👀→다운로드→창 열기 prod 동작 확인(사용자).
- **버그픽스 `build-2f09666`**(발행·설치): ① Slack 👀가 **반응한 메시지의 파일만** 열도록(정확 ts 단일 매칭·폴백 제거; rumi로 실스레드 root=.mov/reply=.md 원인 규명). ② 코드블록 **CJK 정렬**(`pre code` D2Coding 우선 → 한글=2셀). prod 확인 완료.
- **CJK ambiguous-width 정렬 `build-01e533d`**(latest, 발행·설치): 화살표·중점(→ · ◀ ▲) 같은 ambiguous-width로 박스 우측 테두리가 밀리던 것 → `pre code`에 **Sarasa Term 우선**(ambiguous=1셀, 터미널 작성 기준 일치). prod 확인 완료.

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
