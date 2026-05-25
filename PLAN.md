# PLAN — mdLens DocumentGroup 전환

멀티윈도우 상태 공유 버그(마지막 open이 전체 덮어씀) + 다중 파일 오픈 미처리를
공유 `AppState` 싱글톤 제거 = DocumentGroup 전면 전환으로 구조적으로 해결.
사이드바/폴더/아웃라인/퀵오픈은 미사용이라 영구 삭제.

## Current
- [ ] 업데이터 수정본 릴리스 + 부트스트랩: 커밋·푸시 → build-release.sh → gh release → afefc12는 구 업데이터라 새 빌드를 수동 설치(부트스트랩) → 이후부터 자동 견고
- [ ] (선택) 드래그-투-오픈 복원 — 구 onDrop 회귀. CLI 검증 불가라 보류, 사용자 판단 대기. 미복원 시 dead code `markdownExtensions`도 제거
- [ ] 실사용 피드백 대기 — 멀티윈도우/다중오픈/Cmd+R 체감

## Blocked
- (없음)

## Done (압축)
- DocumentGroup 전면 전환(커밋 f3898e6): `MarkdownFileDocument`+`AppSettings`(UserDefaults 영속) 신설, `MarkdownViewerApp`→DocumentGroup(viewing:), `DocumentView` 루트(text+fileURL). 13개 파일 삭제(사이드바4·폴더·아웃라인·퀵오픈·AppState·FileService 등). 실증: 다중 파일→독립 창 2개 = Bug1·2 해결. 근본원인=단일 `AppState` 전 윈도우 공유.
- /verify(50/60) 후속: W1 Reload `focusedSceneValue` 교체(메뉴 enabled + 클릭 실증) · W2 번들 release 반영 · I2 README/CLAUDE.md 동기화. 문서 sync 53/60.
- 릴리스 **build-afefc12** 게시(Latest): Developer ID 서명+notarize(Accepted)+staple. 설치본 f7998d2의 구 업데이터가 다운로드는 했으나 swap 레이스로 미설치 → **수동 swap으로 afefc12 적용 완료**.
- 업데이터 레이스 버그 진단·근본수정: 구조는 "창 닫힘 시 self-swap"이라 Cmd+Q 종료에 졌음. /deep-research(53/60, `docs/research/macos-self-update-patterns/`)로 Sparkle 5원칙 도출 → `Updater.swift` 재작성(스테이징+detached helper+atomic swap+서명/TeamID 검증). 빌드 통과, 검증 게이트·swap 로직 실증.

## Decisions
| 항목 | 결정 | 이유 |
|------|------|------|
| 아키텍처 | DocumentGroup(viewing:) 전면 전환 | 문서당 독립 scene → 공유상태 버그 구조적 소멸, 다중오픈 OS가 처리, 코드 ~40%↓ |
| 사이드바/폴더/아웃라인/퀵오픈 | 영구 삭제 | 사용자 미사용 확정. 워크스페이스 모델이 DocumentGroup과 충돌 |
| theme/fontSize | 공유 `@Observable AppSettings`(UserDefaults 영속) | 창 간 공유가 의도된 설정값. 덤으로 기존 미영속 버그 해결 |
| 파일 URL | `FileDocumentConfiguration.fileURL` | WKWebView 상대경로 이미지 baseURL용. 문서 확인 완료, PoC로 실증 |
| Reload | @FocusedValue로 포커스 창 fileURL 재읽기 | FileDocument는 외부 변경 자동반영 안함. 창별 수동 Cmd+R 유지 |
| 라이브 와처 | 도입 안함 | 현재도 없음(f7998d2에서 FileWatcher 삭제됨). 범위 밖 |
| 업데이터 | homegrown 수정(스테이징+detached helper), Sparkle 미채택 | silent 디자인·commit-hash 스킴 유지, SwiftPM 수동번들에 Sparkle 임베드/서명 복잡. Sparkle 5원칙은 복제 |
| 업데이트 적용 시점 | 종료 시(detached helper)가 아니라 "다운로드 다음 실행에 스테이징분 적용" | 종료 레이스 회피. helper가 PID 종료 polling → atomic swap → relaunch |
