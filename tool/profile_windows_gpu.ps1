# Run after building --release -t tool/windows_gpu_app.dart. Uses throwaway
# profile data and measures the app plus its children, normalized like Task Manager.
param([string]$Executable = 'build/windows/x64/runner/Release/riflay.exe',
      [string]$OutputDirectory = 'build/windows-gpu-profile',
      [switch]$GpuOnly, [string]$VideoOptions = '',
      [ValidateSet('on', 'off')][string]$Renderer = 'off')
$ErrorActionPreference = 'Stop'
$folder = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($folder) | Out-Null
$profile = Join-Path $folder ([guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($profile) | Out-Null
$start = [Diagnostics.ProcessStartInfo]::new([IO.Path]::GetFullPath($Executable))
$start.UseShellExecute = $false
$start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.Environment['APPDATA'] = $profile
$start.Environment['LOCALAPPDATA'] = $profile
$start.Environment['RIFLAY_IMPELLER'] = $Renderer
$start.Environment['RIFLAY_BENCH_GPU_ONLY'] = if ($GpuOnly) { 'true' } else { 'false' }
$start.Environment['RIFLAY_VIDEO_MPV_OPTIONS'] = $VideoOptions
$app = [Diagnostics.Process]::Start($start)
$stdout = $app.StandardOutput.ReadToEndAsync()
$stderr = $app.StandardError.ReadToEndAsync()
$rows = [Collections.Generic.List[object]]::new()
$last = @{}
$watch = [Diagnostics.Stopwatch]::StartNew()
$previous = 0.0
try {
  while (!$app.HasExited -and $watch.Elapsed.TotalSeconds -lt 300) {
    Start-Sleep -Milliseconds 1000
    $at = $watch.Elapsed.TotalSeconds
    $all = @(Get-CimInstance Win32_Process)
    $ids = [Collections.Generic.HashSet[int]]::new()
    [void]$ids.Add($app.Id)
    do {
      $added = $false
      foreach ($process in $all) {
        if ($ids.Contains([int]$process.ParentProcessId)) {
          if ($ids.Add([int]$process.ProcessId)) { $added = $true }
        }
      }
    } while ($added)
    $delta = 0.0
    foreach ($processId in $ids) {
      $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
      if (!$process) { continue }
      $cpu = $process.TotalProcessorTime.TotalSeconds
      if ($last.ContainsKey($processId)) { $delta += [Math]::Max([double]0, [double]($cpu - $last[$processId])) }
      $last[$processId] = $cpu
    }
    $rows.Add([pscustomobject]@{ AtMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); Seconds = $at; CpuPercent = 100 * $delta / ($at - $previous) / [Environment]::ProcessorCount })
    $previous = $at
  }
} finally {
  if (!$app.HasExited) { $app.Kill($true) }
  $app.WaitForExit()
  [IO.File]::WriteAllText((Join-Path $folder 'stdout.log'), $stdout.GetAwaiter().GetResult())
  [IO.File]::WriteAllText((Join-Path $folder 'stderr.log'), $stderr.GetAwaiter().GetResult())
  $rows | Export-Csv (Join-Path $folder 'cpu.csv') -NoTypeInformation
}
Get-Content (Join-Path $folder 'stdout.log')
if ($app.ExitCode -ne 0) {
  Get-Content (Join-Path $folder 'stderr.log')
  throw "Kyapi benchmark failed with exit code $($app.ExitCode); results are not valid."
}
foreach ($line in [IO.File]::ReadAllLines((Join-Path $folder 'stdout.log'))) {
  if ($line -match '^PHASE (software|hardware|lyrics|background) at=(\d+)') {
    $phase = $Matches[1]
    $begin = [long]$Matches[2]
    $length = if ($phase -eq 'background') { 25000 } else { 30000 }
    $samples = @($rows | Where-Object { $_.AtMs -ge ($begin + 1000) -and $_.AtMs -le ($begin + $length) })
    if ($samples.Count -gt 0) {
      $summary = $samples | Measure-Object -Property CpuPercent -Average -Maximum
      Write-Output "$phase CPU total: average=$($summary.Average)%, peak=$($summary.Maximum)% across $($samples.Count) samples"
    }
  }
}
