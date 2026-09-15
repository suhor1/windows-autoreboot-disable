# 윈도우 업데이트 및 자동 재부팅 방지 도구 (Windows Update & Auto-Reboot Control Tool)

**Windows 10** 및 **Windows 11**의 모든 에디션(**Home**, **Pro**, **Enterprise**, **Education**)에서 윈도우 자동 업데이트와 예기치 않은 강제 자동 재부팅을 손쉽게 제어할 수 있는 가볍고 안전한 배치 스크립트 도구입니다.

[English Documentation](README_EN.md)

---

## 주요 특징 (Features)

- **외부 프로그램 설치 불필요**: 별도의 프로그램 설치 없이 윈도우 기본 내장 기능만으로 동작하는 순수 배치(`.bat`) 스크립트입니다.
- **관리자 권한 자동 상승 (UAC Elevation)**: 일반 더블 클릭으로 실행해도 자동으로 UAC 승격 창을 띄워 관리자 권한으로 실행됩니다.
- **실시간 상태 표시**: 실행 시 메뉴 상단에 현재 시스템의 업데이트 활성 상태와 재부팅 방지 적용 상태를 즉시 감지하여 표시합니다.
- **전체 에디션 호환 (Home / Pro / Enterprise)**: 로컬 그룹 정책 편집기(`gpedit.msc`)가 없는 **Windows Home 에디션**에서도 확실하게 차단 및 복구가 동작하도록 설계되었습니다.
- **100% 안전한 원상복구**: 시스템 파일 강제 삭제나 권한 훼손 없이 정책 레지스트리, 서비스 설정, 작업 스케줄러만을 표준적으로 제어하므로 언제든 초기 순정 상태로 깨끗하게 복구할 수 있습니다.

---

## 메뉴 구성 (Menu Options)

```text
======================================================================
          Windows Update & Auto-Reboot Control Tool
======================================================================
 Supported OS: Windows 10 / 11 (Home, Pro, Enterprise, Education)

 [CURRENT SYSTEM STATUS]
 - Windows Update : [ENABLED / DISABLED]
 - Auto-Reboot    : [ALLOWED / BLOCKED]
======================================================================

  [1] Disable Windows Update & Block Auto-Reboot
  [2] Allow Windows Update & Block Auto-Reboot
  [3] Restore Defaults (Allow Update & Allow Auto-Reboot)

  [0] Exit
======================================================================
```

### [1] 윈도우 업데이트 차단 및 자동 재부팅 방지 (Disable Windows Update & Block Auto-Reboot)
> **주요 목적**: 윈도우 업데이트 자체를 완전히 끄고, 컴퓨터가 마음대로 재부팅되는 것을 완벽히 차단합니다.
- 윈도우 자동 업데이트 검색 및 다운로드를 차단합니다.
- 윈도우 업데이트 관련 핵심 서비스(`wuauserv`, `UsoSvc`, `WaaSMedicSvc`)를 중지하고 비활성화합니다.
- 로그인된 사용자가 작업 중일 때 강제 자동 재부팅을 방지합니다.
- UpdateOrchestrator의 자동 재부팅 예약 작업(`Reboot`, `Reboot_AC`, `Reboot_Battery`)을 비활성화합니다.

### [2] 윈도우 업데이트 허용 및 자동 재부팅 방지 (Allow Windows Update & Block Auto-Reboot)
> **주요 목적**: 보안 업데이트는 정상적으로 설치하되, 작업 중인 컴퓨터가 예기치 않게 저절로 재부팅되는 것만 막고 싶을 때 사용합니다.
- 윈도우 업데이트 서비스들을 정상 동작(수동/자동) 상태로 켜둡니다.
- 설치 및 재부팅 전에 사용자에게 알림을 주도록 정책을 구성합니다.
- 사용자가 로그인되어 있을 때 시스템이 임의로 재부팅하는 것을 방지합니다.
- 작업 스케줄러의 강제 재부팅 트리거를 비활성화하여 백그라운드 재부팅을 차단합니다.

### [3] 기본값 복원 (Restore Defaults - Allow Update & Allow Auto-Reboot)
> **주요 목적**: 윈도우 순정 기본 설정 상태로 100% 되돌립니다.
- 적용되었던 모든 커스텀 레지스트리 및 그룹 정책 값을 삭제하거나 기본값으로 복원합니다.
- 윈도우 업데이트 서비스(`wuauserv`, `UsoSvc`, `WaaSMedicSvc`)의 시작 유형을 윈도우 기본값으로 복구합니다.
- 비활성화되었던 재부팅 예약 작업 스케줄러를 다시 활성화합니다.

### [0] 종료 (Exit)
- 스크립트를 안전하게 종료합니다.

---

## 기술 세부 사항 (Technical Details)

| 구성 요소 | [1] 업데이트 차단 + 재부팅 방지 | [2] 업데이트 허용 + 재부팅 방지 | [3] 기본값 복원 (초기 상태) |
| :--- | :--- | :--- | :--- |
| **AU 정책 레지스트리** | `NoAutoUpdate=1`<br>`AUOptions=1` | `NoAutoUpdate=0`<br>`AUOptions=2` | 설정 삭제 / 기본값 복구 |
| **재부팅 정책 레지스트리** | `NoAutoRebootWithLoggedOnUsers=1`<br>`AlwaysAutoRebootAtScheduledTime=0`<br>`AUPowerManagement=0` | `NoAutoRebootWithLoggedOnUsers=1`<br>`AlwaysAutoRebootAtScheduledTime=0`<br>`AUPowerManagement=0` | 설정 삭제 / 기본값 복구 |
| **`wuauserv` (업데이트 서비스)** | `Disabled` (사용 안 함 / 중지) | `Demand` (수동 / 실행) | `Demand` (수동 - 기본값) |
| **`UsoSvc` (오케스트레이터 서비스)** | `Disabled` (사용 안 함 / 중지) | `Auto` (지연된 시작 / 실행) | `Auto` (지연된 시작 - 기본값) |
| **`WaaSMedicSvc` (메딕 서비스)** | `Start=4` (사용 안 함) | `Start=3` (수동) | `Start=3` (수동 - 기본값) |
| **`UpdateOrchestrator` 작업 스케줄러** | `Reboot*` 작업 비활성화 | `Reboot*` 작업 비활성화 | `Reboot*` 작업 활성화 |

---

## 실행 방법 (How to Run)

1. 이 저장소의 최신 코드를 다운로드하거나 클론합니다.
2. [`WindowsUpdateControl.bat`](WindowsUpdateControl.bat) 파일을 **더블 클릭**하여 실행합니다.
3. **사용자 계정 컨트롤(UAC)** 창이 나타나면 **'예'**를 눌러 관리자 권한을 승인합니다.
4. 콘솔 메뉴에서 원하는 번호(`1`, `2`, `3`, `0`)를 입력하고 **Enter**를 누르면 즉시 적용됩니다.

---

## 라이선스 (License)

이 프로젝트는 [MIT License](LICENSE)를 따릅니다.
