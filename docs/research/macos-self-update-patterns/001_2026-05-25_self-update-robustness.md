---
topic: macos-self-update-patterns
seq: 001
date: 2026-05-25
status: reviewed
previous: null
sources_tier: 1
---

# macOS 비샌드박스 Developer ID 앱 self-update 견고성 리서치

대상 컨텍스트: Developer ID 서명 + notarized, Mac App Store 밖 GitHub Releases(zip) 배포, **비샌드박스** 앱(= mdLens). homegrown updater 재설계를 위한 기술 조사.

핵심 1차 소스는 시점 무관 권위 소스(Sparkle 공식 docs/GitHub, Apple 공식 docs), 보안/패턴 자료는 최근 12개월 이내 우선. 모든 인용에 URL + 날짜 명시.

---

## 1. Sparkle 프레임워크 — 아키텍처와 설치 메커니즘

### 1.1 전체 흐름 (appcast → download → verify)

Sparkle은 macOS de-facto 표준 업데이터. 현재 최신 릴리스 **2.9.2 (2026-05-17)**, macOS 10.13+. 동작에 앱 코드가 거의 필요 없고 웹 서버의 정적 파일만 있으면 됨 ([GitHub README](https://github.com/sparkle-project/Sparkle)).

1. **appcast XML feed** — `Info.plist`의 `SUFeedURL`이 HTTPS appcast를 가리킴. appcast는 RSS feed + Sparkle namespace(`http://www.andymatuschak.org/xml-namespaces/sparkle`) 확장. 각 `<item>`은 `sparkle:version`(machine-readable, `CFBundleVersion` 기반 증가형), `<enclosure url=... length=... type=... sparkle:edSignature=...>`를 가짐 ([Publishing docs](https://sparkle-project.org/documentation/publishing/)).
2. **download** — HTTPS 강제. 아카이브는 zip/dmg/tar(.xz)/Apple Archive/pkg 지원.
3. **서명 검증 (이중)** — "Updates are verified using **EdDSA signatures and Apple Code Signing**" ([README](https://github.com/sparkle-project/Sparkle)):
   - **EdDSA(Ed25519)**: `./bin/generate_keys`가 개인키를 login Keychain에 저장하고 공개키를 `SUPublicEDKey`(Info.plist)에 넣음. `generate_appcast`(또는 수동 `./bin/sign_update`)가 아카이브를 서명해 `sparkle:edSignature`를 생성. 다운로드된 아카이브는 appcast의 ed25519 서명으로 검증 → 서버가 침해돼도 위조 업데이트 차단 ([eddsa-migration](https://sparkle-project.org/documentation/eddsa-migration/), [Publishing](https://sparkle-project.org/documentation/publishing/)).
   - **Apple Code Signing**: 새 번들의 Developer ID 서명이 **현재 실행 중인 앱과 동일한 서명 신원**인지 검증. 두 검증 중 하나라도 실패하면 설치 거부. EdDSA 키 회전 시 "Apple cert 또는 EdDSA key 중 하나만 바꾸는 업데이트"로 안전 회전 가능(둘 다 동시에 바꾸면 신뢰 사슬 단절).
   - 선택적으로 `SURequireSignedFeed`로 appcast/릴리스 노트 자체도 서명 → 서버 침해 시 다른 위치로 유도 차단.

### 1.2 결정적 질문 — Sparkle은 언제/어떻게 설치하는가

**핵심: Sparkle은 in-process로 설치하지 않는다. 별도 helper 프로세스(`Autoupdate`)가 호스트 앱 종료 후 설치한다.**

- **install-on-quit가 기본 모델**. delegate API가 이를 드러냄:
  `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` — "quit 시점에 설치 예정"일 때 호출. 문서 명시: **"In either case Sparkle will always attempt to install the update when the app terminates."** ([SPUUpdaterDelegate](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html)).
- **UI driver 단계** ([SPUUserDriver](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUserDriver.html)):
  - `showReadyToInstallAndRelaunch:` — "Install & Relaunch" 단계 UI.
  - `showInstallingUpdateWithApplicationTerminated:retryTerminatingApplication:` — 앱이 아직 살아 있으면 Sparkle이 **quit 이벤트를 보내** 종료를 유도. 종료가 지연/취소되면 완료까지 대기.
  - `showUpdateInstalledAndRelaunched:` — 설치 완료 후 콜백. **"오래된 번들은 더 이상 참조 금지"** 명시(= 구 번들은 이미 새 것으로 교체됨).
- **별도 프로세스 = `Autoupdate` 도구** (repo 최상위 `Autoupdate/`, `InstallerLauncher/`, `InstallerConnection/`, `InstallerStatus/`, `Downloader/` 디렉터리로 확인). `sparkle-cli`가 같은 메커니즘을 노출:
  - 업데이트가 있으면 대상 앱을 종료시키고 즉시 설치, 살아 있었으면 재실행.
  - **`--defer-install`** = "대상 앱이 스스로 종료된 뒤 설치를 마치기 위해 **spawned process를 남긴다**" — detached helper 패턴의 직접 증거.
  - **`--application`** = 종료를 감시하고 relaunch할 앱 경로 지정.
  - 설치 실패(기존 번들 대체 권한 없음) 시 **exit status 8** ([sparkle-cli docs](https://sparkle-project.org/documentation/sparkle-cli/)).
- **swap는 atomic**. README: "Supports ... **atomic-safe installs**." Sparkle 2는 설치 파일 작업을 atomic 처리하도록 재작성. APFS/HFS+의 `rename(2)` 의미론(아래 §2)을 활용해 기존 `.app`을 새 번들로 안전 교체 — crash 시에도 중간 손상 상태가 남지 않음 ([Sparkle docs](https://sparkle-project.org/documentation/), [README](https://github.com/sparkle-project/Sparkle)).
- **종료 대기 → relaunch 흐름**: helper가 타겟 앱(PID 또는 Bundle ID 기준) 종료를 감시 → 종료되면 atomic swap → `NSWorkspace`로 새 버전 relaunch ([Sparkle discussion #2427, 2023-08-28](https://github.com/sparkle-project/Sparkle/discussions/2427)).

### 1.3 왜 별도 프로세스인가 (in-process 불가 이유)

Sparkle 메인테이너(zorgiepoo) 측 설명(요지, WebSearch 경유 2차 인용 — 원문 재확인 권장): Autoupdate는 helper이자 잠재적 privileged installer 역할이며, 마지막 설치 단계가 authorization API를 쓸 수 있어 XPC service가 될 수 없고, XPC service는 앱의 lifespan에 묶이므로 installer에 부적합하다는 것. → 따라서 독립 `Autoupdate` 도구가 최종 extraction/validation/install/relaunch를 수행 (Sparkle UI XPC issues 토론).

정리: ① installer는 **호스트 앱보다 오래 살아야** 함(앱이 죽은 뒤 그 번들을 교체해야 하므로). XPC service는 앱 lifecycle에 종속되어 부적합. ② installer는 필요 시 **권한 상승(authorization)** 을 할 수 있어야 함.

비샌드박스 앱에서도 XPC services(`Installer.xpc`/`Downloader.xpc`)는 **선택**(샌드박스 앱에서만 필수). 하지만 최종 swap+relaunch는 어느 경우든 별도 `Autoupdate` 도구 몫 ([Sandboxing docs](https://sparkle-project.org/documentation/sandboxing/)).

### 1.4 다운로드 빌드의 code signature/notarization 검증

- EdDSA 서명 검증(아카이브 무결성·진위) + Apple Code Signing 신원 일치 검증(새 번들 Developer ID == 현재 앱)을 **설치 전** 수행.
- Sparkle은 진단으로 `codesign --deep --verify <path>` 권장. 배포 시 앱과 모든 helper tool은 Hardened Runtime + Developer ID 서명 + notarize ([Sparkle docs](https://sparkle-project.org/documentation/)).
- notarization 자체는 Sparkle이 런타임에 "검증"하지 않음 — Gatekeeper가 quarantine된 번들 첫 실행 시 stapled ticket/online lookup으로 확인. Sparkle은 quarantine 속성 처리와 translocation 해제를 자동으로 함(§4).

---

## 2. 핵심 견고성 원리 — 왜 실행 중 앱의 self-replace는 위험한가

### 2.1 무엇이 race/fail 하는가

실행 중인 앱이 자기 `.app`을 `rm`/`mv`하고 shell script로 relaunch하는 방식의 실패 지점:

1. **열린 파일/동적 로드 race**: 앱이 실행 중일 때 번들을 삭제해도 커널은 열린 inode를 유지하지만, 앱이 **이후 동적으로 리소스(nib, 프레임워크, 코드 페이지)를 로드**하려 하면 경로를 못 찾아 crash/오작동 ([unix.stackexchange #706437, 2022-06-18](https://unix.stackexchange.com/questions/706437/avoid-symlink-race-rcondition-with-mv-in-bash)). macOS는 lazy하게 번들 리소스를 로드하므로 "앱이 다 떴으니 안전"이 성립하지 않음.
2. **종료 타이밍 race**: `NSRunningApplication.terminate()`는 **실제 종료 전에 반환될 수 있음**. 종료 완료는 `isTerminated`(KVO) 또는 `NSWorkspaceDidTerminateApplicationNotification`으로만 확인 가능 ([Apple: NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate%28%29)). 스크립트가 고정 `sleep`으로 종료를 가정하면 비결정적.
3. **비원자적 mv/rm**: shell `rm` 후 `mv`는 두 단계라 중간에 crash/전원 차단 시 번들이 **사라지거나 반쪽** 상태로 남음(atomicity 미보장). Apple도 "실행 파일을 in-place로 수정하는 것은 잘못된 예"로 명시 ([Apple: updating Mac software](https://developer.apple.com/documentation/security/updating-mac-software)).
4. **스크립트 자체가 죽는 problem**: relaunch 스크립트를 앱이 spawn하면 앱의 자식 프로세스 → 앱이 죽으면 (detach 안 했을 때) 같이 죽거나 SIGHUP 받을 수 있음. 스크립트가 교체 완료 전에 죽으면 앱이 사라짐.
5. **translocation/권한 race**: 앱이 read-only mount나 Gatekeeper translocated 경로에서 실행 중이면 `mv` 경로 불일치/권한 오류(§4).

### 2.2 올바른 패턴 — detached helper가 앱보다 오래 산다

업계 표준(= Sparkle이 하는 것):

1. 앱이 **별도 helper 프로세스를 spawn하고 detach** — 앱의 프로세스 그룹/lifecycle에서 분리(앱이 죽어도 helper는 산다). Sparkle의 `Autoupdate`, `sparkle-cli --defer-install`의 "spawned process를 남긴다"가 정확히 이것.
2. helper가 **호스트 PID 종료를 결정적으로 대기** — `NSWorkspaceDidTerminateApplicationNotification`/`isTerminated`/`waitpid` 등으로 실제 종료 확인(고정 sleep 금지).
3. 종료 확인 후 **atomic swap** — `rename(2)`로 새 번들을 기존 경로에 교체. `rename()`은 atomic이며 "crash 시에도 `new`의 인스턴스가 항상 존재"를 보장(old/new가 동일 파일시스템일 때) ([Apple: rename(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/rename.2.html)). 실무에선 "새 번들을 같은 부모 디렉터리의 임시 이름으로 펼친 뒤 → 구 번들과 exchange/rename"하여 어느 시점에도 유효한 `.app`이 존재하게 함.
4. **설치 전 검증** — 새 번들의 서명 신원이 구 앱과 일치하는지(downgrade/대체 공격 차단), 아카이브 무결성(EdDSA/체크섬).
5. swap 후 **`NSWorkspace`로 relaunch** → helper 종료.

Apple DTS 공식 입장도 동일: 앱은 자기 자신을 교체할 수 없으니 **메인 앱보다 오래 사는 non-sandboxed helper**가 필요하고, Sparkle이 open-source working example ([Apple 포럼 thread/737503, 2023-09](https://developer.apple.com/forums/thread/737503)).

---

## 3. 대안 패턴

### 3.1 Install-on-next-launch (staging)

업데이트를 다운로드/검증해 staging 위치에 두고, **다음 앱 시작 시 UI 로드 전에 swap**하거나 별도 부트스트랩이 처리. Electron `autoUpdater`(Squirrel.Mac)가 이 모델: `quitAndInstall()`로 재시작 후 설치하거나, "성공적으로 다운로드된 업데이트는 **다음 시작 시 자동 적용**" ([Electron autoUpdater](https://www.electronjs.org/docs/latest/api/auto-updater)).
- 장점: 실행 중 swap race를 회피(앱이 안 떠 있을 때 교체). 구현 단순.
- 단점: 여전히 "교체 주체"가 문제 — 앱 자신이 startup 초기에 swap하면 §2.1 동적 로드 race가 그대로(이미 자기 번들에서 코드를 매핑 중). 그래서 Squirrel.Mac도 ShipIt이라는 **별도 프로세스**가 swap을 담당. 즉 staging도 결국 detached helper와 결합해야 안전.

### 3.2 SMAppService / privileged helper

- macOS 13+ 표준은 **`SMAppService`** (구 `SMJobBless`/`SMLoginItemSetEnabled` deprecated). 앱 번들 내부 helper executable(LaunchAgent/LaunchDaemon/LoginItem)을 `register()`/`unregister()`로 등록 ([Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)). privileged helper는 `Contents/Library/LaunchServices`에 위치.
- **언제 필요한가**: `/Applications`(시스템 전역) 쓰기에 현재 사용자가 권한이 없을 때 root 데몬으로 swap을 수행해야 하는 경우. 일상적 self-update에는 보통 불필요(§3.3).

### 3.3 /Applications 쓰기 권한 — elevation 필요 시점

- **`~/Applications`(사용자 폴더) 설치**: elevation **불필요**. 번들 소유자가 현재 사용자이므로 helper가 그대로 swap 가능 ([velopack #50, 2024-03-12](https://github.com/velopack/velopack/issues/50)).
- **`/Applications`(시스템 전역) 설치**: 첫 설치 시 사용자가 Finder로 드래그-복사했다면 보통 **번들 소유자 = 그 사용자**가 되어 admin 없이도 교체 가능한 경우가 많음. 다만 다른 사용자/installer가 설치했거나 폴더 ACL이 제한적이면 admin 자격 필요 → 그때만 authorization prompt(또는 SMAppService 데몬).
- Sparkle은 이 분기를 자동 처리: 권한이 충분하면 prompt 없이, 부족하면 authorization prompt를 띄움. 권한 없어 교체 실패 시 `sparkle-cli`는 exit 8 ([SPUUserDriver authorization 노트](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUserDriver.html), [sparkle-cli](https://sparkle-project.org/documentation/sparkle-cli/)).
- **DMG 배포 관행**: DMG에 `/Applications` symlink를 넣어 사용자가 Applications로 복사하도록 유도(소유권을 사용자에게 부여) ([Sparkle docs](https://sparkle-project.org/documentation/)).

---

## 4. 흔한 함정 & notarization stapling 영향

### 4.1 Notarization stapling

- 공증 후 ticket을 `stapler`로 번들에 붙이면(`xcrun stapler staple App.app`) 오프라인에서도 Gatekeeper가 검증 가능 ([Apple: notarizing](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [customizing-the-notarization-workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/customizing-the-notarization-workflow)).
- **번들 무결성**: 공증/서명 후 번들 내부 파일을 **하나라도 수정/추가하면 code signature가 깨지고 공증 무효** ([SO #59356345, 2019](https://stackoverflow.com/questions/59356345/how-to-update-a-macos-bundle-without-breaking-notarization)). → 업데이트는 **반드시 외부에서 공증·stapled된 전체 번들을 통째로 swap**해야 함. in-place 부분 패치(개별 파일 덮어쓰기) 금지. (Sparkle의 delta update는 변경 파일만 다운로드하지만 적용 결과는 완전한 새 번들이어야 서명/공증이 유효 — delta 적용 후 최종 swap되는 번들의 서명 무결성을 Sparkle이 검증. 적용 메커니즘 세부는 corpus 미확인, 원문 재확인 권장.)
- **ZIP에는 staple 불가**: ticket은 ZIP 자체에 못 붙임 → `.app`에 먼저 `stapler staple` 후 ZIP으로 재압축해야 오프라인 Gatekeeper 검증 보장 ([publicspace.net, 2019](https://www.publicspace.net/blog/notarization/), [Apple customizing-workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/customizing-the-notarization-workflow)). GitHub Releases zip 배포 시 **stapled .app을 zip에 넣어야** 함(공증만 하고 staple 안 한 채 zip하면 첫 실행 시 온라인 lookup 의존 → 오프라인 실패 가능).
- zip 생성은 framework symlink 보존: `ditto -c -k --sequesterRsrc --keepParent MyApp.app MyApp.zip` ([Sparkle Publishing](https://sparkle-project.org/documentation/publishing/)).

### 4.2 Gatekeeper translocation

브라우저로 다운로드된 quarantine `.app`은 Gatekeeper가 **임의 read-only 경로로 translocate**해 실행할 수 있음. 이 상태에서 `mv` 기반 self-update는 경로 불일치/권한 오류 ([christiantietze.de, 2022-07-12](https://christiantietze.de/posts/2022/07/mac-app-notarization-workflow/)). Sparkle은 translocation 감지·해제 + quarantine 처리를 내장. homegrown은 이를 직접 처리해야 함.

### 4.3 보안 함정 — updater 자체가 공격 표면

updater는 full user privilege로 인터넷에서 executable을 받아 설치 → 침해 시 RCE 채널 ([doyensec, 2026-02-16](https://blog.doyensec.com/2026/02/16/electron-safe-updater.html)). Sparkle조차 helper/XPC에서 로컬 권한 상승 취약점이 있었음:
- **Sparkle 2.7.3 (2025-09-08)** 로컬 exploit 수정 ([discussion #2764](https://github.com/sparkle-project/Sparkle/discussions/2764)):
  - Installer XPC root escalation — (a) 기만적 authorization prompt로 가짜 번들에 임의 pkg 설치 유도, (b) **race condition**: legit 앱이 통신하기 전에 `Autoupdate`에 timed XPC 메시지를 보내 악성 번들 설치를 트리거(tool이 root로 실행 중일 때).
  - 수정: non-HTTPS URL 거부, bundle identity 검증, unsigned/ad-hoc 앱 설치 거부, client↔service 간 **동일 dev team identifier 일치 요구**.
- **CVE-2025-10016 (2025-10-27)**: 구버전 XPC가 호출자 미검증 → 로컬 권한 상승. 최신은 연결 client 서명 doubly-verify ([afine.com](https://afine.com/threats-of-unvalidated-xpc-clients-on-macos/)).
- **시사점(homegrown)**: helper가 root로 돌거나 authorization을 쥐면 **반드시 호출자(connecting client) code signing 신원을 검증**해야 함. 설치 대상 번들의 서명 신원이 현재 앱과 일치하는지, 다운로드 URL이 HTTPS인지 강제.

### 4.4 서명 순서 함정

서명은 안쪽부터: XPC services/helper 먼저 → framework → 앱(**`--deep` 사용 금지**). 순서를 어기거나 `--deep`을 쓰면 XPC 통신 실패/authorization 오류 ([steipete, 2025-06-05](https://steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears), [Sparkle Sandboxing](https://sparkle-project.org/documentation/sandboxing/)).

---

## 5. 대안 비교표

| 항목 | Sparkle (2.9.2) | Squirrel.Mac (Electron autoUpdater) | Homegrown(올바르게 구현) | Homegrown(앱 self-rm/mv + script) |
|---|---|---|---|---|
| 설치 시점 | install-on-quit + 자동 background | quitAndInstall / next-launch | detached helper가 종료 후 | 종료 시 script (위험) |
| swap 주체 | 별도 `Autoupdate` 프로세스 | 별도 `ShipIt` 프로세스 | 별도 detached helper(필수) | 앱 자식 script(취약) |
| atomic swap | O (rename 기반, atomic-safe) | O (ShipIt) | rename(2) 직접 구현 시 O | X (rm+mv 2단계) |
| 서명 검증 | EdDSA + Apple Code Signing 이중 | 코드 서명 신원 일치 | 직접 구현 필요 | 보통 누락 |
| translocation/quarantine | 자동 처리 | 부분 | 직접 처리 | 미처리 → 실패 |
| notarization staple 안전 | 전체 번들 swap | 전체 번들 swap | 전체 번들 swap이면 O | in-place면 무효화 |
| 보안 감사 이력 | 활발(2.7.3, CVE 대응) | 보통 | 자체 책임 | 매우 취약 |
| 적합 시나리오 | 표준 macOS 네이티브 앱 | Electron 앱 | Sparkle 의존 회피 필요시 | **사용 금지** |

**권장**: 견고성·보안·유지보수 관점에서 **Sparkle 채택이 압도적 표준**. homegrown을 유지해야 한다면 최소한 (1) 앱과 분리된 detached helper가 (2) PID 종료를 결정적으로 대기한 뒤 (3) `rename(2)` 기반 atomic swap을 하고 (4) 새 번들 서명 신원을 검증하고 (5) 전체 stapled 번들을 통째 교체하는 Sparkle의 5요소를 그대로 복제해야 함. 앱이 직접 자기 번들을 rm/mv하는 방식은 §2.1의 race로 인해 신뢰 불가 — 폐기 대상.

---

## 6. mdLens 재설계 시사점 (요약)

- 현재 mdLens가 "앱 종료/window-close에서 self-replace + script relaunch"라면 §2.1 race(동적 로드 crash, 종료 타이밍, 비원자 mv, 번들 소실)에 그대로 노출.
- 비샌드박스 + Developer ID + zip 배포라는 조건은 **Sparkle의 sweet spot**. XPC services 없이도(비샌드박스라 선택) `Autoupdate` + EdDSA + Apple Code Signing만으로 동작. 기존 commit-hash 태그 스킴을 appcast `sparkle:version`(증가형 `CFBundleVersion`)에 매핑 필요.
- zip 배포 시 **stapled .app을 zip에 담아야** 오프라인 Gatekeeper 통과(§4.1).
- homegrown 유지 시: detached helper 바이너리를 별도로 두고(앱 번들 내 helper tool), 앱은 helper를 spawn+detach → helper가 `NSWorkspaceDidTerminateApplicationNotification` 대기 → `rename(2)` swap → `NSWorkspace` relaunch. 서명 신원 일치 검증 필수.

---

## Review Transparency Note
- 수집 환경 제약: subagent 컨텍스트라 Task tool(Sonnet/Haiku swarm 4 slot) 발행 불가 → orchestrator의 WebSearch×4 + WebFetch×4로 동등 대체. Codex 7 slot(Gemini/Mini×5/GPT-5.4)은 정상 발행. raw: `.raw/2026-05-25/`.
- §1.3 "왜 별도 프로세스" 근거 중 메인테이너 인용은 Sparkle UI XPC issues 토론(WebSearch 경유) — 1차 원문 재확인 권장.
- Gemini 수집의 Medium URL 1건(`...861f...`)은 의심 URL로 본문 인용에서 제외. EdDSA+Apple Code Signing 이중 검증 사실은 GitHub README/Sparkle docs가 독립 확인.
- notarization/ZIP staple 기초 일부 소스는 2019년(메커니즘 불변)이나 Apple 공식 docs가 동일 사실 재확인 → 현시점 유효.
