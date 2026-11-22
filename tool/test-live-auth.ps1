$ErrorActionPreference='Stop'
$session=Import-Clixml -LiteralPath (Join-Path $env:LOCALAPPDATA 'ZyYouxueApiTest\sxz-jiashu.credential.xml')
$credential=Import-Clixml -LiteralPath (Join-Path $env:LOCALAPPDATA 'ZyYouxueApiTest\sxz-student.credential.xml')
try {
    $env:JIASHU_LIVE_SESSION=$session.GetNetworkCredential().Password
    $env:JIASHU_LIVE_PASSWORD=$credential.GetNetworkCredential().Password
    $env:JIASHU_LIVE_USER=$credential.UserName
    flutter test test/live_auth_test.dart --no-pub
    if($LASTEXITCODE -ne 0){throw 'Automatic-login integration test failed; see sanitized output'}
} finally {
    Remove-Item Env:\JIASHU_LIVE_SESSION,Env:\JIASHU_LIVE_PASSWORD,Env:\JIASHU_LIVE_USER -ErrorAction SilentlyContinue
    $session.Password.Dispose()
    $credential.Password.Dispose()
}
