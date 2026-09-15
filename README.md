# Windows Update & Auto-Reboot Control Tool

A lightweight, standalone batch utility to manage Windows Update and automatic reboot behavior on **Windows 10** and **Windows 11** across all editions (**Home**, **Pro**, **Enterprise**, **Education**).

---

## Features

- **No Third-Party Dependencies**: Pure native Windows batch script with inline elevation.
- **UAC Self-Elevation**: Automatically requests Administrator privileges if launched normally.
- **Real-Time Status Overview**: Displays current Windows Update and Auto-Reboot status at the top of the menu.
- **Universal Edition Support**: Specially engineered to work reliably on both **Home** and **Pro/Enterprise** editions.
- **Clean & Reversible**: Applies non-destructive registry and service changes that can be completely restored to factory defaults anytime.

---

## Menu Options

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

### 1. Disable Windows Update & Block Auto-Reboot
- Disables Windows Update automatic checks and downloads.
- Stops and disables `wuauserv` (Windows Update) and `UsoSvc` (Update Orchestrator).
- Disables `WaaSMedicSvc` (Windows Update Medic Service) via registry.
- Blocks automatic restarts when users are logged on.
- Disables scheduled reboot trigger tasks in `UpdateOrchestrator`.

### 2. Allow Windows Update & Block Auto-Reboot
- Enables Windows Update services and allows normal update checks/downloads (configured to notify before installing or rebooting).
- Blocks unexpected automatic reboots while users are logged on or working.
- Disables scheduled reboot tasks so reboots will not happen automatically in the background.

### 3. Restore Defaults (Allow Update & Allow Auto-Reboot)
- Reverts all custom policies and registry overrides.
- Restores `wuauserv`, `UsoSvc`, and `WaaSMedicSvc` services to default startup types.
- Re-enables scheduled reboot tasks in `UpdateOrchestrator`.

---

## Technical Details

| Component | Mode 1: Block All | Mode 2: Update OK, Block Reboot | Mode 3: Restore Default |
| :--- | :--- | :--- | :--- |
| **`AU` Policy Registry** | `NoAutoUpdate=1`<br>`AUOptions=1` | `NoAutoUpdate=0`<br>`AUOptions=2` | Deleted / Reverted |
| **Reboot Policy Registry** | `NoAutoRebootWithLoggedOnUsers=1`<br>`AlwaysAutoRebootAtScheduledTime=0`<br>`AUPowerManagement=0` | `NoAutoRebootWithLoggedOnUsers=1`<br>`AlwaysAutoRebootAtScheduledTime=0`<br>`AUPowerManagement=0` | Deleted / Reverted |
| **`wuauserv` Service** | Disabled / Stopped | Demand (Manual) / Started | Demand (Manual) |
| **`UsoSvc` Service** | Disabled / Stopped | Auto (Delayed) / Started | Auto (Delayed) / Started |
| **`WaaSMedicSvc` Service** | Start=4 (Disabled) | Start=3 (Manual) | Start=3 (Manual) |
| **`UpdateOrchestrator` Tasks** | `Reboot*` tasks disabled | `Reboot*` tasks disabled | `Reboot*` tasks enabled |

---

## How to Run

1. Download or clone this repository.
2. Double-click `WindowsUpdateControl.bat`.
3. When prompted by **User Account Control (UAC)**, click **Yes** to grant Administrator privileges.
4. Select your desired option (`1`, `2`, `3`, or `0`) and press **Enter**.

---

## License

MIT License
