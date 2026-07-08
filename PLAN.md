# PLAN — mdLens (로컬 마크다운/HTML 뷰어 + Quick Look)

macOS 네이티브 마크다운/HTML 뷰어. SwiftUI + WKWebView + swift-markdown. SwiftPM(Xcode 프로젝트 없음).
렌더 뷰어(.md) + raw `.html` 직접 로드 + Finder Quick Look 확장(`mdLensQL.appex`).
자동 업데이트: `build-<hash>` 태그. 상세는 README(SSOT).

## Current
- [ ] **issue #2 재검증** — Slack 삭제로 `Window("Connect Slack")` scene + MenuBarExtra가 사라짐(= 이전 PLAN이 적어둔 "scene 최소화" 워크어라운드 그 자체, `build-a8d9909`). 26.4 신고자(sungmopark)에게 **새 빌드로 문서 창이 생성되는지** 확인 요청. 창 정상 → issue #2 close(원인=추가 scene). 여전히 0개 → 순수 26.4 DocumentGroup 회귀 확정.

## Blocked
- (없음)

## Done (압축)
- **Slack 👀 인입 (제거됨 `build-a8d9909`, 발행·설치)**: Socket Mode 리스너로 👀→다운로드→자기 창 열기. self-only 필터(a936e6d)·sleep/resume 자동복구(7db6123)까지 하드닝했으나, **Slack이 .md/.html 네이티브 인라인 렌더를 제공하면서 기능 목적 소멸 → 전체 삭제**(8파일 + MenuBarExtra + Connect Slack scene). 순수 로컬 뷰어 + Quick Look로 단순화. 상세: git history.
- **`.html` 뷰어**(7dea980): `loadFileURL` 직접 로드(마크다운 파이프라인 우회).
- **Quick Look 확장**(8dbc327): `.md`/`.html` Finder 미리보기. `MarkdownCore` 공유 모듈 분리 후 `mdLensQL.appex`가 WKWebView+MarkdownRenderer로 풀 충실도 렌더. 핵심: QL 확장 WKWebView에서 JS 실행됨(최소 3 entitlement 한정).
- **CJK ambiguous-width 정렬**(01e533d): `pre code`에 Sarasa Term 우선(ambiguous=1셀, 터미널 작성 기준 일치).
- **베이스**: DocumentGroup 전환 + 자동 업데이터. 상세는 git history.

## Backlog
- **코드블록 CJK 정렬 폰트 무의존화**: 현재 Sarasa Term 설치자만 완전 정렬. 미설치 동료 위해 webfont(CDN) 로드 검토.

## Decisions
| 항목 | 결정 | 이유 |
|------|------|------|
| Slack 인입 | **제거** | Slack이 .md/.html 인라인 렌더 제공 → 워크어라운드 목적 소멸. 백그라운드·토큰·Socket 재연결 유지보수 제거로 앱 단순화(+ issue #2 용의 scene 제거) |
| 뷰어 | DocumentGroup(파일당 1창, 공유 싱글턴 없음) | read-only 문서앱. 창별 독립 상태 |
| 서명 | `Developer ID Application: Sugarscone (5FK7UUGMX3)` | Gatekeeper 통과 + 자동업데이트 서명 검증 |
| 자동업데이트 | `build-<7hash>` 태그·gh release·다음 실행 시 스왑 | 무폴링·무프롬프트. 상세 README |

## Gotchas
- `swift build`만으로는 ad-hoc 서명(commitHash="dev") → 자동업데이트 비활성. 실제 배포는 `scripts/build-release.sh`만(해시 주입·Developer ID 서명·공증).
- `CFBundleShortVersionString` 손대지 말 것 — 스크립트가 `git HEAD`에서 설정.
- `main` 보호 브랜치(문서상 `dev` 작업 권장이나, 현재 단독 작업자라 main 직접 커밋 허용).
