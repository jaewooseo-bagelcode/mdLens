# PLAN — mdLens DocumentGroup 전환

멀티윈도우 상태 공유 버그(마지막 open이 전체 덮어씀) + 다중 파일 오픈 미처리를
공유 `AppState` 싱글톤 제거 = DocumentGroup 전면 전환으로 구조적으로 해결.
사이드바/폴더/아웃라인/퀵오픈은 미사용이라 영구 삭제.

## Current
- [ ] 커밋 (사용자 요청 시) — 별도 브랜치 권장. 릴리스 시엔 scripts/build-release.sh로 재빌드 필요
- [ ] (선택) 드래그-투-오픈 복원 — 구 onDrop 회귀. CLI 검증 불가라 보류, 사용자 판단 대기

## Blocked
- (없음)

## Done (압축)
- 검토: 두 버그 근본원인 = 단일 `AppState` 전 윈도우 공유. 상세 git/대화 참조.
- DocumentGroup 전면 전환: `MarkdownFileDocument`+`AppSettings`(UserDefaults 영속) 신설, `MarkdownViewerApp`→DocumentGroup(viewing:), `DocumentView`가 루트(text+fileURL). 13개 파일 삭제(사이드바4·폴더·아웃라인·퀵오픈·AppState·FileService 등). 실증: 다중 파일→독립 창 2개 = Bug1·2 해결.
- /verify(50/60) 후속 수정: W1 Reload를 `focusedSceneValue`로 교체(메뉴 enabled=true + 클릭 무크래시 실증) · W2 번들에 release 바이너리 반영+서명 · I2 README/CLAUDE.md DocumentGroup 구조로 동기화. 클린 release 빌드 통과.

## Decisions
| 항목 | 결정 | 이유 |
|------|------|------|
| 아키텍처 | DocumentGroup(viewing:) 전면 전환 | 문서당 독립 scene → 공유상태 버그 구조적 소멸, 다중오픈 OS가 처리, 코드 ~40%↓ |
| 사이드바/폴더/아웃라인/퀵오픈 | 영구 삭제 | 사용자 미사용 확정. 워크스페이스 모델이 DocumentGroup과 충돌 |
| theme/fontSize | 공유 `@Observable AppSettings`(UserDefaults 영속) | 창 간 공유가 의도된 설정값. 덤으로 기존 미영속 버그 해결 |
| 파일 URL | `FileDocumentConfiguration.fileURL` | WKWebView 상대경로 이미지 baseURL용. 문서 확인 완료, PoC로 실증 |
| Reload | @FocusedValue로 포커스 창 fileURL 재읽기 | FileDocument는 외부 변경 자동반영 안함. 창별 수동 Cmd+R 유지 |
| 라이브 와처 | 도입 안함 | 현재도 없음(f7998d2에서 FileWatcher 삭제됨). 범위 밖 |
