# Run beside a release build, start playback + Listen Together during capture:
# powershell -ExecutionPolicy Bypass -File tool/profile_windows_memory.ps1 -Executable C:\Riflay\riflay.exe
# PrivateMiB is committed process memory; WorkingSetMiB is resident RAM.
# Child processes are separate rows so WebView2 usage is visible.
param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [ValidateRange(10, 3600)][int]$Seconds = 120,
    [string]$Output = "riflay-memory.csv"
)
$ErrorActionPreference = 'Stop'
$app = Start-Process -FilePath (Resolve-Path $Executable).Path -PassThru
$rows = [System.Collections.Generic.List[object]]::new()
$summary = [System.Collections.Generic.List[object]]::new()
$clock = [System.Diagnostics.Stopwatch]::StartNew()
while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
    $app.Refresh()
    if ($app.HasExited) { break }
    $processes = @(Get-CimInstance Win32_Process)
    $ids = [System.Collections.Generic.HashSet[int]]::new()
    [void]$ids.Add($app.Id)
    do {
        $added = $false
        foreach ($process in $processes) {
            if ($ids.Contains([int]$process.ParentProcessId)) {
                if ($ids.Add([int]$process.ProcessId)) { $added = $true }
            }
        }
    } while ($added)
    $groupPrivate = 0L
    $groupWorkingSet = 0L
    $rootPrivate = 0L
    $childCount = 0
    foreach ($processId in $ids) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) { continue }
        $groupPrivate += $process.PrivateMemorySize64
        $groupWorkingSet += $process.WorkingSet64
        if ($processId -eq $app.Id) {
            $rootPrivate = $process.PrivateMemorySize64
        } else {
            $childCount++
        }
        $rows.Add([pscustomobject]@{
            Seconds = [math]::Round($clock.Elapsed.TotalSeconds, 1)
            ProcessId = $processId
            Name = $process.ProcessName
            PrivateMiB = [math]::Round($process.PrivateMemorySize64 / 1MB, 1)
            WorkingSetMiB = [math]::Round($process.WorkingSet64 / 1MB, 1)
            Threads = $process.Threads.Count
            Handles = $process.HandleCount
        })
    }
    $summary.Add([pscustomobject]@{
        Seconds = [math]::Round($clock.Elapsed.TotalSeconds, 1)
        RootPrivateMiB = [math]::Round($rootPrivate / 1MB, 1)
        ChildrenPrivateMiB = [math]::Round(($groupPrivate - $rootPrivate) / 1MB, 1)
        GroupPrivateMiB = [math]::Round($groupPrivate / 1MB, 1)
        GroupWorkingSetMiB = [math]::Round($groupWorkingSet / 1MB, 1)
        ChildProcesses = $childCount
    })
    Start-Sleep -Seconds 1
}
$rows | Export-Csv -Path $Output -NoTypeInformation
$summaryPath = [System.IO.Path]::ChangeExtension($Output, '.summary.csv')
$summary | Export-Csv -Path $summaryPath -NoTypeInformation
Write-Host "Saved process details to $Output and group totals to $summaryPath."
$app.Refresh()
if ($app.HasExited -and $app.ExitCode -ne 0) {
    throw "Riflay exited with code $($app.ExitCode)."
}
