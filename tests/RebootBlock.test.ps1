# 재부팅 차단 로직 검증 (프레임워크 없음, 관리자 권한 불필요)
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File tests\RebootBlock.test.ps1
# WUC_UX_KEY / WUC_TASK 환경 변수로 실제 시스템 대신 HKCU 테스트 키를 보게 한다.
$ErrorActionPreference = 'Stop'
$bat = (Resolve-Path (Join-Path $PSScriptRoot '..\WindowsUpdateControl.bat')).Path
$regKey = 'HKCU\Software\WUControlTest'
$psKey = "Registry::$regKey"
$okTask = '\WUControlTestOk'
$badTask = '\WUControlTestBad'
$tickTask = '\WUControlTestTick'
$failures = 0

# 주어진 명령줄(/tr)로 임시 작업을 만들어 한 번 실행하고, 끝난 뒤의 "마지막 결과" 값을 돌려준다
function Invoke-TempTask($name, $tr) {
    $escaped = $tr.Replace('"', '\"')
    cmd /c "schtasks /create /tn $name /tr `"$escaped`" /sc once /st 00:00 /f >nul 2>&1"
    cmd /c "schtasks /run /tn $name >nul 2>&1"
    foreach ($i in 1..30) {
        Start-Sleep -Milliseconds 500
        $last = @((schtasks /query /tn $name /v /fo csv | ConvertFrom-Csv)[0].psobject.Properties)[6].Value
        if ($last -notin '267009', '267011') { return $last }   # 실행 중 / 아직 실행 안 됨
    }
    return "timeout($last)"
}

function Assert($condition, $name) {
    if ($condition) { Write-Host "PASS  $name" }
    else { Write-Host "FAIL  $name"; $script:failures++ }
}

function Invoke-Bat($verb, $task = '\WUControlTest\NoSuchTask') {
    $env:WUC_UX_KEY = $regKey
    $env:WUC_TASK = $task
    $out = cmd /c "`"$bat`" $verb" 2>&1 | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}

function Set-Hours($start, $end) {
    Set-ItemProperty $psKey ActiveHoursStart ([int]$start)
    Set-ItemProperty $psKey ActiveHoursEnd ([int]$end)
}

# 안전장치: 동사를 모르는 구버전은 인자를 무시하고 UAC 승격 창을 띄우므로 실행하지 않는다.
$src = Get-Content $bat -Raw
if ($src -notmatch '"/tick"' -or $src -notmatch '"/status"') {
    Write-Host 'FAIL  /tick, /status 동사가 구현되어 있지 않음'
    exit 1
}

New-Item $psKey -Force | Out-Null
try {
    # 1. /tick: 지금 시각부터 18시간을 사용 시간으로 기록한다
    $before = (Get-Date).Hour
    $r = Invoke-Bat '/tick'
    $after = (Get-Date).Hour
    $p = Get-ItemProperty $psKey
    $k = Get-Item $psKey
    Assert ($r.Code -eq 0) '/tick 종료 코드 0'
    Assert ($p.ActiveHoursStart -in $before, $after) "/tick ActiveHoursStart = 현재 시 (실제 $($p.ActiveHoursStart))"
    Assert ($p.ActiveHoursEnd -eq (($p.ActiveHoursStart + 18) % 24)) "/tick ActiveHoursEnd = 시작+18시간 (실제 $($p.ActiveHoursEnd))"
    Assert ($k.GetValueKind('ActiveHoursStart') -eq 'DWord' -and $k.GetValueKind('ActiveHoursEnd') -eq 'DWord') '/tick 값 형식 DWORD'

    # 2. /status: 사용 시간이 현재를 덮는지 실제 값으로 판정한다
    $h = (Get-Date).Hour
    Assert ((Invoke-Bat '/status').Out -match 'ACTIVE_HOURS_COVER_NOW=YES') 'tick 직후 → 덮음'
    Set-Hours (($h + 2) % 24) (($h + 5) % 24)
    Assert ((Invoke-Bat '/status').Out -match 'ACTIVE_HOURS_COVER_NOW=NO') '현재가 범위 밖 → 안 덮음'
    Set-Hours (($h + 20) % 24) (($h + 1) % 24)
    Assert ((Invoke-Bat '/status').Out -match 'ACTIVE_HOURS_COVER_NOW=YES') '범위 안(시작이 더 이른 방향으로 20시간 전) → 덮음'
    Set-Hours $h $h
    Assert ((Invoke-Bat '/status').Out -match 'ACTIVE_HOURS_COVER_NOW=NO') '시작=종료 → 안 덮음'

    # 3. /status: 갱신 작업 유무와 최종 판정
    Set-Hours $h (($h + 18) % 24)
    $r = Invoke-Bat '/status'
    Assert ($r.Out -match 'KEEPER_TASK=MISSING') '작업 없음 → MISSING'
    Assert ($r.Out -match 'REBOOT_BLOCK=NOT BLOCKED') '작업 없으면 NOT BLOCKED'
    # 작업이 "있다"가 아니라 "마지막 실행이 성공했다"여야 OK (현재 사용자 권한의 임시 작업으로 검증)
    Invoke-TempTask $okTask 'cmd /c exit 0' | Out-Null
    Invoke-TempTask $badTask 'cmd /c exit 3' | Out-Null
    $r = Invoke-Bat '/status' $okTask
    Assert ($r.Out -match 'KEEPER_TASK=OK') '마지막 실행 성공 → OK'
    Assert ($r.Out -match 'REBOOT_BLOCK=BLOCKED' -and $r.Out -notmatch 'NOT BLOCKED') '덮음 + 작업 성공 → BLOCKED'
    $r = Invoke-Bat '/status' $badTask
    Assert ($r.Out -match 'KEEPER_TASK=FAILING, last result 3') '마지막 실행 실패 → FAILING'
    Assert ($r.Out -match 'REBOOT_BLOCK=NOT BLOCKED') '작업이 실패 중이면 NOT BLOCKED'
    Set-Hours (($h + 2) % 24) (($h + 5) % 24)
    Assert ((Invoke-Bat '/status' $okTask).Out -match 'REBOOT_BLOCK=NOT BLOCKED') '작업이 성공해도 범위 밖이면 NOT BLOCKED'

    # 4. 예약 작업 명령줄은 schtasks /tr 한도(261자) 안이어야 한다
    $env:WUC_UX_KEY = $null
    $real = (cmd /c "`"$bat`" /tickcmd" 2>&1 | Out-String).Trim()
    Assert ($real.Length -gt 0 -and $real.Length -le 261) "작업 명령줄 길이 $($real.Length) <= 261"
    Assert ($real -match 'HKLM\\SOFTWARE\\Microsoft\\WindowsUpdate\\UX\\Settings') '작업 명령줄이 실제 UX 키를 가리킴'

    # 5. 회귀: schtasks 는 /tr 안의 작은따옴표를 큰따옴표로 바꿔 저장한다.
    #    명령줄을 실제 예약 작업에 넣었다 실행해도 사용 시간이 기록되어야 한다.
    Remove-ItemProperty $psKey ActiveHoursStart, ActiveHoursEnd
    $env:WUC_UX_KEY = $regKey
    $tick = (cmd /c "`"$bat`" /tickcmd" | Out-String).Trim()
    $last = Invoke-TempTask $tickTask $tick
    $p = Get-ItemProperty $psKey
    Assert ($last -eq '0') "예약 작업으로 실행한 tick 의 마지막 결과 0 (실제 $last)"
    Assert ($p.ActiveHoursStart -eq (Get-Date).Hour -or $p.ActiveHoursStart -eq (Get-Date).AddMinutes(-1).Hour) "예약 작업으로 실행한 tick 이 사용 시간을 기록 (실제 '$($p.ActiveHoursStart)')"
}
finally {
    Remove-Item $psKey -Recurse -Force -ErrorAction SilentlyContinue
    $okTask, $badTask, $tickTask | ForEach-Object { cmd /c "schtasks /delete /tn $_ /f >nul 2>&1" }
    $env:WUC_UX_KEY = $null; $env:WUC_TASK = $null
}

if ($failures) { Write-Host "`n$failures 개 실패"; exit 1 }
Write-Host "`n모두 통과"
