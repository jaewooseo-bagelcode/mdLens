# PLAN — mdLens DocumentGroup 전환

멀티윈도우 상태 공유 버그(마지막 open이 전체 덮어씀) + 다중 파일 오픈 미처리를
공유 `AppState` 싱글톤 제거 = DocumentGroup 전면 전환으로 구조적으로 해결.
사이드바/폴더/아웃라인/퀵오픈은 미사용이라 영구 삭제.

## Current
- [ ] (선택) 드래그-투-오픈 복원 결정 — 구 onDrop 회귀. 복원 시 직접 드롭 테스트 필요

## Blocked
- (없음)

## Done (압축)
- DocumentGroup 전면 전환(f3898e6): 단일 `AppState` 공유가 근본원인 → 문서당 독립 scene. `MarkdownFileDocument`+`AppSettings`(UserDefaults 영속) 신설, `DocumentView` 루트, 13개 파일 삭제. 다중 파일→독립 창 실증 = Bug1·2(마지막 open 덮어씀/다중오픈) 해결. /verify 50/60 후속(Reload `focusedSceneValue` 등). 릴리스 build-afefc12.
- 자동 업데이터 견고화(ffe7b20): 구 "창 닫힘 시 self-swap"이 Cmd+Q 레이스로 미설치됨 → /deep-research(53/60, `docs/research/macos-self-update-patterns/`)로 Sparkle 5원칙 도출 → `Updater.swift` 재작성(실행 시 스테이징 + 다음 실행에 detached helper가 PID 종료 대기→atomic swap→relaunch + 서명/TeamID 검증). 릴리스 build-ffe7b20 → 부트스트랩 swap으로 설치 확인(현재 설치=Latest=ffe7b20). 이후 자동 업데이트 자립.
- 실사용 확인: 멀티윈도우 독립성·자동 업데이트 사용자 확인 완료.
- md/파일 링크 클릭 동작: `visitLink`이 상대·절대·~ 경로를 절대 `file://`로 해석(앵커/http/mailto는 보존), WebView에 nav delegate 추가(.md→mdLens 새 창, 기타 파일/웹→기본 앱, #앵커→스크롤). 근본원인=링크 destination 미해석 + nav delegate 부재. end-to-end 실증(절대경로 56링크 깨끗 렌더).

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
