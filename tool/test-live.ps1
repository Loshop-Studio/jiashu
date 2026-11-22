$ErrorActionPreference='Stop'
$sessionPath=Join-Path $env:LOCALAPPDATA 'ZyYouxueApiTest\sxz-jiashu.credential.xml'
$credential=Import-Clixml -LiteralPath $sessionPath
try {
    $env:JIASHU_LIVE_SESSION=$credential.GetNetworkCredential().Password
    flutter test test/live_account_test.dart
    if($LASTEXITCODE -ne 0){throw 'Live integration test failed; see sanitized test output'}
} finally {
    Remove-Item Env:\JIASHU_LIVE_SESSION -ErrorAction SilentlyContinue
    $credential.Password.Dispose()
}
