$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Installs an isolated worker into ./vexpax2 without changing the old panel.
$root = Join-Path (Get-Location).Path 'vexpax2'
$ports = @(@(18787, 'php.pid'), @(18443, 'proxy.pid'))
foreach ($item in $ports) {
    $listener = Get-NetTCPConnection -LocalPort $item[0] -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $listener) { continue }
    $pidPath = Join-Path $root ('configuration\' + $item[1])
    $installedPid = 0
    if ((-not (Test-Path -LiteralPath $pidPath)) -or
        (-not [int]::TryParse((Get-Content -LiteralPath $pidPath -Raw).Trim(), [ref]$installedPid)) -or
        ($installedPid -ne $listener.OwningProcess)) {
        throw "Порт $($item[0]) уже занят. Если vexpax2 установлен в другой папке, повторите команду из той же папки."
    }
}
$configuration = Join-Path $root 'configuration'
$runtime = Join-Path $root 'runtime'
$phpDir = Join-Path $runtime 'php'
$public = Join-Path $root 'public'
$null = New-Item -ItemType Directory -Force -Path $configuration, (Join-Path $root 'plugins'), $phpDir, $public

$phpUrl = 'https://downloads.php.net/~windows/releases/archives/php-8.5.11-nts-Win32-vs17-x64.zip'
$phpSha256 = '0ea96e0d2b9b737a6036f05cf4e95c49313faa6d0f27bd97edb2742503f0c043'
$phpExe = Join-Path $phpDir 'php.exe'
if (-not (Test-Path -LiteralPath $phpExe)) {
    $archive = Join-Path $runtime 'php.zip'
    Invoke-WebRequest -Uri $phpUrl -OutFile $archive
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $phpSha256) { throw 'Проверка SHA-256 архива PHP не прошла.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $phpDir -Force
    Remove-Item -LiteralPath $archive -Force
}
try {
    & $phpExe -v | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'PHP failed' }
} catch {
    $redistributable = Join-Path $runtime 'vc_redist.x64.exe'
    Invoke-WebRequest -Uri 'https://aka.ms/vc14/vc_redist.x64.exe' -OutFile $redistributable
    $signature = Get-AuthenticodeSignature -FilePath $redistributable
    if ($signature.Status -ne 'Valid' -or
        $signature.SignerCertificate.Subject -notlike '*Microsoft Corporation*') {
        throw 'Не удалось проверить подпись Microsoft Visual C++ Redistributable.'
    }
    $setup = Start-Process -FilePath $redistributable -ArgumentList @('/install', '/quiet', '/norestart') -Verb RunAs -Wait -PassThru
    if ($setup.ExitCode -notin @(0, 3010)) { throw 'Не удалось установить Microsoft Visual C++ Redistributable.' }
    Remove-Item -LiteralPath $redistributable -Force
    & $phpExe -v | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'PHP не запускается после установки Microsoft Visual C++ Redistributable.' }
}

$tokenPath = Join-Path $configuration 'token'
if (-not (Test-Path -LiteralPath $tokenPath)) {
    $random = New-Object byte[] 32
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($random) } finally { $generator.Dispose() }
    $token = ([BitConverter]::ToString($random)).Replace('-', '').ToLowerInvariant()
    [IO.File]::WriteAllText($tokenPath, $token, [Text.Encoding]::ASCII)
}
$token = ([IO.File]::ReadAllText($tokenPath)).Trim()

$pfxPath = Join-Path $configuration 'server.pfx'
$passwordPath = Join-Path $configuration 'tls-password'
if (-not (Test-Path -LiteralPath $pfxPath)) {
    $random = New-Object byte[] 24
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($random) } finally { $generator.Dispose() }
    $pfxPassword = ([BitConverter]::ToString($random)).Replace('-', '')
    [IO.File]::WriteAllText($passwordPath, $pfxPassword, [Text.Encoding]::ASCII)
    $certificate = New-SelfSignedCertificate -DnsName 'vexpax2-worker' `
        -CertStoreLocation 'Cert:\CurrentUser\My' -KeyExportPolicy Exportable `
        -NotAfter (Get-Date).AddYears(2)
    $securePassword = ConvertTo-SecureString -String $pfxPassword -AsPlainText -Force
    Export-PfxCertificate -Cert $certificate -FilePath $pfxPath -Password $securePassword | Out-Null
    Remove-Item -LiteralPath ("Cert:\CurrentUser\My\" + $certificate.Thumbprint) -Force
} else {
    if (-not (Test-Path -LiteralPath $passwordPath)) { throw 'Найден сертификат без пароля. Восстановите конфигурацию.' }
    $pfxPassword = ([IO.File]::ReadAllText($passwordPath)).Trim()
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($pfxPath, $pfxPassword)
}
$sha256 = [Security.Cryptography.SHA256]::Create()
try { $fingerprint = ([BitConverter]::ToString($sha256.ComputeHash($certificate.RawData))).Replace('-', '').ToLowerInvariant() }
finally { $sha256.Dispose() }

[IO.File]::WriteAllBytes((Join-Path $public 'index.php'), [Convert]::FromBase64String('PD9waHAKZGVjbGFyZShzdHJpY3RfdHlwZXM9MSk7CgpoZWFkZXIoJ0NvbnRlbnQtVHlwZTogYXBwbGljYXRpb24vanNvbjsgY2hhcnNldD11dGYtOCcpOwpoZWFkZXIoJ0NhY2hlLUNvbnRyb2w6IG5vLXN0b3JlJyk7CmhlYWRlcignWC1Db250ZW50LVR5cGUtT3B0aW9uczogbm9zbmlmZicpOwoKJHBhdGggPSBwYXJzZV91cmwoJF9TRVJWRVJbJ1JFUVVFU1RfVVJJJ10gPz8gJy8nLCBQSFBfVVJMX1BBVEgpOwppZiAoJHBhdGggIT09ICcvcGluZycgfHwgKCRfU0VSVkVSWydSRVFVRVNUX01FVEhPRCddID8/ICcnKSAhPT0gJ0dFVCcpIHsKICAgIGh0dHBfcmVzcG9uc2VfY29kZSg0MDQpOwogICAgZWNobyBqc29uX2VuY29kZShbJ2Vycm9yJyA9PiAnbm90X2ZvdW5kJ10pOwogICAgZXhpdDsKfQoKJGV4cGVjdGVkID0gdHJpbSgoc3RyaW5nKSBAZmlsZV9nZXRfY29udGVudHMoZGlybmFtZShfX0RJUl9fKSAuICcvY29uZmlndXJhdGlvbi90b2tlbicpKTsKJGF1dGhvcml6YXRpb24gPSAoc3RyaW5nKSAoJF9TRVJWRVJbJ0hUVFBfQVVUSE9SSVpBVElPTiddID8/ICcnKTsKJHByb3ZpZGVkID0gc3RybmNtcCgkYXV0aG9yaXphdGlvbiwgJ0JlYXJlciAnLCA3KSA9PT0gMAogICAgPyBzdWJzdHIoJGF1dGhvcml6YXRpb24sIDcpCiAgICA6ICcnOwppZiAoJGV4cGVjdGVkID09PSAnJyB8fCAhaGFzaF9lcXVhbHMoJGV4cGVjdGVkLCAkcHJvdmlkZWQpKSB7CiAgICBodHRwX3Jlc3BvbnNlX2NvZGUoNDAxKTsKICAgIGVjaG8ganNvbl9lbmNvZGUoWydlcnJvcicgPT4gJ3VuYXV0aG9yaXplZCddKTsKICAgIGV4aXQ7Cn0KCmVjaG8ganNvbl9lbmNvZGUoWwogICAgJ29rJyA9PiB0cnVlLAogICAgJ3NlcnZpY2UnID0+ICd2ZXhwYXgyLXdvcmtlcicsCiAgICAndmVyc2lvbicgPT4gMSwKICAgICdzZXJ2ZXJfdGltZScgPT4gZ21kYXRlKCdjJyksCl0sIEpTT05fVU5FU0NBUEVEX1NMQVNIRVMpOwo='))
[IO.File]::WriteAllBytes((Join-Path $root 'manage.ps1'), [Convert]::FromBase64String('77u/cGFyYW0oCiAgICBbUGFyYW1ldGVyKFBvc2l0aW9uID0gMCldCiAgICBbVmFsaWRhdGVTZXQoJ3N0YXJ0JywgJ3N0b3AnLCAncmVzdGFydCcsICdzdGF0dXMnLCAna2V5JywgJ3VuaW5zdGFsbCcpXQogICAgW3N0cmluZ10kQWN0aW9uID0gJ3N0YXR1cycKKQokRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJ1N0b3AnCiRyb290ID0gKFJlc29sdmUtUGF0aCAtTGl0ZXJhbFBhdGggKFNwbGl0LVBhdGggLVBhcmVudCAkTXlJbnZvY2F0aW9uLk15Q29tbWFuZC5QYXRoKSkuUGF0aAokY29uZmlndXJhdGlvbiA9IEpvaW4tUGF0aCAkcm9vdCAnY29uZmlndXJhdGlvbicKCmZ1bmN0aW9uIEdldC1Xb3JrZXJQcm9jZXNzKFtzdHJpbmddJG5hbWUsIFtzdHJpbmddJGV4cGVjdGVkKSB7CiAgICAkcGlkUGF0aCA9IEpvaW4tUGF0aCAkY29uZmlndXJhdGlvbiAiJG5hbWUucGlkIgogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHBpZFBhdGgpKSB7IHJldHVybiAkbnVsbCB9CiAgICAkcHJvY2Vzc0lkID0gMAogICAgaWYgKC1ub3QgW2ludF06OlRyeVBhcnNlKChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHBpZFBhdGggLVJhdykuVHJpbSgpLCBbcmVmXSRwcm9jZXNzSWQpKSB7IHJldHVybiAkbnVsbCB9CiAgICAkcHJvY2VzcyA9IEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzIC1GaWx0ZXIgIlByb2Nlc3NJZD0kcHJvY2Vzc0lkIiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQogICAgaWYgKCRudWxsIC1lcSAkcHJvY2VzcyAtb3IgJHByb2Nlc3MuQ29tbWFuZExpbmUgLW5vdGxpa2UgIiokZXhwZWN0ZWQqIikgeyByZXR1cm4gJG51bGwgfQogICAgcmV0dXJuICRwcm9jZXNzCn0KCmZ1bmN0aW9uIFN0b3AtV29ya2VyIHsKICAgIGZvcmVhY2ggKCRlbnRyeSBpbiBAKEAoJ3Byb3h5JywgJ3Byb3h5LnBzMScpLCBAKCdwaHAnLCAncGhwLmV4ZScpKSkgewogICAgICAgICRwcm9jZXNzID0gR2V0LVdvcmtlclByb2Nlc3MgJGVudHJ5WzBdICRlbnRyeVsxXQogICAgICAgIGlmICgkbnVsbCAtbmUgJHByb2Nlc3MpIHsgU3RvcC1Qcm9jZXNzIC1JZCAkcHJvY2Vzcy5Qcm9jZXNzSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIH0KICAgICAgICAkcGlkUGF0aCA9IEpvaW4tUGF0aCAkY29uZmlndXJhdGlvbiAiJCgkZW50cnlbMF0pLnBpZCIKICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJHBpZFBhdGggLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlCiAgICB9Cn0KCnN3aXRjaCAoJEFjdGlvbikgewogICAgJ3N0YXJ0JyB7CiAgICAgICAgJHBocCA9IEdldC1Xb3JrZXJQcm9jZXNzICdwaHAnICdwaHAuZXhlJwogICAgICAgICRwcm94eSA9IEdldC1Xb3JrZXJQcm9jZXNzICdwcm94eScgJ3Byb3h5LnBzMScKICAgICAgICBpZiAoJG51bGwgLWVxICRwaHAgLWFuZCAoR2V0LU5ldFRDUENvbm5lY3Rpb24gLUxvY2FsUG9ydCAxODc4NyAtU3RhdGUgTGlzdGVuIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKSkgewogICAgICAgICAgICB0aHJvdyAn0J/QvtGA0YIgMTg3ODcg0YPQttC1INC30LDQvdGP0YIuIHZleHBheDIg0LfQsNC/0YPRidC10L0g0LjQtyDQtNGA0YPQs9C+0Lkg0L/QsNC/0LrQuCDQuNC70Lgg0L/QvtGA0YIg0LjRgdC/0L7Qu9GM0LfRg9C10YIg0LTRgNGD0LPQsNGPINC/0YDQvtCz0YDQsNC80LzQsC4nCiAgICAgICAgfQogICAgICAgIGlmICgkbnVsbCAtZXEgJHByb3h5IC1hbmQgKEdldC1OZXRUQ1BDb25uZWN0aW9uIC1Mb2NhbFBvcnQgMTg0NDMgLVN0YXRlIExpc3RlbiAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsKICAgICAgICAgICAgdGhyb3cgJ9Cf0L7RgNGCIDE4NDQzINGD0LbQtSDQt9Cw0L3Rj9GCLiB2ZXhwYXgyINC30LDQv9GD0YnQtdC9INC40Lcg0LTRgNGD0LPQvtC5INC/0LDQv9C60Lgg0LjQu9C4INC/0L7RgNGCINC40YHQv9C+0LvRjNC30YPQtdGCINC00YDRg9Cz0LDRjyDQv9GA0L7Qs9GA0LDQvNC80LAuJwogICAgICAgIH0KICAgICAgICBpZiAoJG51bGwgLWVxICRwaHApIHsKICAgICAgICAgICAgJHBocEV4ZSA9IEpvaW4tUGF0aCAkcm9vdCAncnVudGltZVxwaHBccGhwLmV4ZScKICAgICAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHBocEV4ZSkpIHsgdGhyb3cgJ1BIUCDQvdC1INGD0YHRgtCw0L3QvtCy0LvQtdC9LiDQn9C+0LLRgtC+0YDQuNGC0LUg0LrQvtC80LDQvdC00YMg0YPRgdGC0LDQvdC+0LLQutC4LicgfQogICAgICAgICAgICAkaW5kZXggPSBKb2luLVBhdGggJHJvb3QgJ3B1YmxpY1xpbmRleC5waHAnCiAgICAgICAgICAgICRwdWJsaWMgPSBKb2luLVBhdGggJHJvb3QgJ3B1YmxpYycKICAgICAgICAgICAgJHBocCA9IFN0YXJ0LVByb2Nlc3MgLUZpbGVQYXRoICRwaHBFeGUgLUFyZ3VtZW50TGlzdCBAKCctUycsICcxMjcuMC4wLjE6MTg3ODcnLCAnLXQnLCAiYCIkcHVibGljYCIiLCAiYCIkaW5kZXhgIiIpIC1Xb3JraW5nRGlyZWN0b3J5ICRyb290IC1XaW5kb3dTdHlsZSBIaWRkZW4gLVBhc3NUaHJ1CiAgICAgICAgICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRjb25maWd1cmF0aW9uICdwaHAucGlkJykgLVZhbHVlICRwaHAuSWQgLU5vTmV3bGluZQogICAgICAgIH0KICAgICAgICBpZiAoJG51bGwgLWVxICRwcm94eSkgewogICAgICAgICAgICAkcHJveHlTY3JpcHQgPSBKb2luLVBhdGggJHJvb3QgJ3Byb3h5LnBzMScKICAgICAgICAgICAgJHByb3h5ID0gU3RhcnQtUHJvY2VzcyAtRmlsZVBhdGggJ3Bvd2Vyc2hlbGwuZXhlJyAtQXJndW1lbnRMaXN0IEAoJy1Ob1Byb2ZpbGUnLCAnLUV4ZWN1dGlvblBvbGljeScsICdCeXBhc3MnLCAnLUZpbGUnLCAiYCIkcHJveHlTY3JpcHRgIiIpIC1Xb3JraW5nRGlyZWN0b3J5ICRyb290IC1XaW5kb3dTdHlsZSBIaWRkZW4gLVBhc3NUaHJ1CiAgICAgICAgICAgIFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRjb25maWd1cmF0aW9uICdwcm94eS5waWQnKSAtVmFsdWUgJHByb3h5LklkIC1Ob05ld2xpbmUKICAgICAgICB9CiAgICAgICAgV3JpdGUtT3V0cHV0ICd2ZXhwYXgyINC30LDQv9GD0YnQtdC9LicKICAgIH0KICAgICdzdG9wJyB7CiAgICAgICAgU3RvcC1Xb3JrZXIKICAgICAgICBXcml0ZS1PdXRwdXQgJ3ZleHBheDIg0L7RgdGC0LDQvdC+0LLQu9C10L0uJwogICAgfQogICAgJ3Jlc3RhcnQnIHsKICAgICAgICBTdG9wLVdvcmtlcgogICAgICAgICYgJE15SW52b2NhdGlvbi5NeUNvbW1hbmQuUGF0aCBzdGFydAogICAgfQogICAgJ3N0YXR1cycgewogICAgICAgICRwaHAgPSBHZXQtV29ya2VyUHJvY2VzcyAncGhwJyAncGhwLmV4ZScKICAgICAgICAkcHJveHkgPSBHZXQtV29ya2VyUHJvY2VzcyAncHJveHknICdwcm94eS5wczEnCiAgICAgICAgaWYgKCRudWxsIC1uZSAkcGhwIC1hbmQgJG51bGwgLW5lICRwcm94eSkgeyBXcml0ZS1PdXRwdXQgJ3ZleHBheDIg0YDQsNCx0L7RgtCw0LXRgi4nIH0KICAgICAgICBlbHNlIHsgV3JpdGUtT3V0cHV0ICd2ZXhwYXgyINC+0YHRgtCw0L3QvtCy0LvQtdC9INC40LvQuCDQt9Cw0L/Rg9GJ0LXQvSDRh9Cw0YHRgtC40YfQvdC+LicgfQogICAgfQogICAgJ2tleScgewogICAgICAgIEdldC1Db250ZW50IC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRjb25maWd1cmF0aW9uICdjb25uZWN0aW9uLmtleScpIC1SYXcKICAgIH0KICAgICd1bmluc3RhbGwnIHsKICAgICAgICBTdG9wLVdvcmtlcgogICAgICAgICRyZXNvbHZlZCA9IFtJTy5QYXRoXTo6R2V0RnVsbFBhdGgoJHJvb3QpLlRyaW1FbmQoJ1wnKQogICAgICAgIGlmIChbSU8uUGF0aF06OkdldEZpbGVOYW1lKCRyZXNvbHZlZCkgLW5lICd2ZXhwYXgyJyAtb3IgLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAoSm9pbi1QYXRoICRyZXNvbHZlZCAnY29uZmlndXJhdGlvbicpKSkgewogICAgICAgICAgICB0aHJvdyAn0J3QtdCx0LXQt9C+0L/QsNGB0L3Ri9C5INC/0YPRgtGMINGD0LTQsNC70LXQvdC40Y8uJwogICAgICAgIH0KICAgICAgICBSZW1vdmUtTmV0RmlyZXdhbGxSdWxlIC1EaXNwbGF5TmFtZSAndmV4cGF4MiB3b3JrZXIgcG9ydCAxODQ0MycgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAgICAgICBSZW1vdmUtSXRlbSAtTGl0ZXJhbFBhdGggJHJlc29sdmVkIC1SZWN1cnNlIC1Gb3JjZQogICAgICAgIFdyaXRlLU91dHB1dCAndmV4cGF4MiDRg9C00LDQu9GR0L0uJwogICAgfQp9Cg=='))
[IO.File]::WriteAllBytes((Join-Path $root 'proxy.ps1'), [Convert]::FromBase64String('77u/JEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdTdG9wJwokcm9vdCA9IFNwbGl0LVBhdGggLVBhcmVudCAkTXlJbnZvY2F0aW9uLk15Q29tbWFuZC5QYXRoCiRwYXNzd29yZCA9IChHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkcm9vdCAnY29uZmlndXJhdGlvblx0bHMtcGFzc3dvcmQnKSAtUmF3KS5UcmltKCkKJGNlcnRpZmljYXRlID0gW1NlY3VyaXR5LkNyeXB0b2dyYXBoeS5YNTA5Q2VydGlmaWNhdGVzLlg1MDlDZXJ0aWZpY2F0ZTJdOjpuZXcoCiAgICAoSm9pbi1QYXRoICRyb290ICdjb25maWd1cmF0aW9uXHNlcnZlci5wZngnKSwgJHBhc3N3b3JkLAogICAgW1NlY3VyaXR5LkNyeXB0b2dyYXBoeS5YNTA5Q2VydGlmaWNhdGVzLlg1MDlLZXlTdG9yYWdlRmxhZ3NdOjpFeHBvcnRhYmxlCikKJGxpc3RlbmVyID0gW05ldC5Tb2NrZXRzLlRjcExpc3RlbmVyXTo6bmV3KFtOZXQuSVBBZGRyZXNzXTo6QW55LCAxODQ0MykKJGxpc3RlbmVyLlN0YXJ0KCkKdHJ5IHsKICAgIHdoaWxlICgkdHJ1ZSkgewogICAgICAgICRjbGllbnQgPSAkbGlzdGVuZXIuQWNjZXB0VGNwQ2xpZW50KCkKICAgICAgICAkY2xpZW50LlJlY2VpdmVUaW1lb3V0ID0gNzAwMAogICAgICAgICRjbGllbnQuU2VuZFRpbWVvdXQgPSA3MDAwCiAgICAgICAgJHRscyA9ICRudWxsCiAgICAgICAgJHVwc3RyZWFtID0gJG51bGwKICAgICAgICB0cnkgewogICAgICAgICAgICAkdGxzID0gW05ldC5TZWN1cml0eS5Tc2xTdHJlYW1dOjpuZXcoJGNsaWVudC5HZXRTdHJlYW0oKSwgJGZhbHNlKQogICAgICAgICAgICAkdGxzLkF1dGhlbnRpY2F0ZUFzU2VydmVyKAogICAgICAgICAgICAgICAgJGNlcnRpZmljYXRlLCAkZmFsc2UsIFtTZWN1cml0eS5BdXRoZW50aWNhdGlvbi5Tc2xQcm90b2NvbHNdOjpUbHMxMiwgJGZhbHNlCiAgICAgICAgICAgICkKICAgICAgICAgICAgJHVwc3RyZWFtID0gW05ldC5Tb2NrZXRzLlRjcENsaWVudF06Om5ldygnMTI3LjAuMC4xJywgMTg3ODcpCiAgICAgICAgICAgICR1cHN0cmVhbS5SZWNlaXZlVGltZW91dCA9IDcwMDAKICAgICAgICAgICAgJHVwc3RyZWFtLlNlbmRUaW1lb3V0ID0gNzAwMAogICAgICAgICAgICAkc2VydmVyU3RyZWFtID0gJHVwc3RyZWFtLkdldFN0cmVhbSgpCiAgICAgICAgICAgICRidWZmZXIgPSBOZXctT2JqZWN0IGJ5dGVbXSAxNjM4NAogICAgICAgICAgICAkcmVxdWVzdCA9IFtJTy5NZW1vcnlTdHJlYW1dOjpuZXcoKQogICAgICAgICAgICB3aGlsZSAoJHJlcXVlc3QuTGVuZ3RoIC1sdCA4MTkyKSB7CiAgICAgICAgICAgICAgICAkY291bnQgPSAkdGxzLlJlYWQoJGJ1ZmZlciwgMCwgJGJ1ZmZlci5MZW5ndGgpCiAgICAgICAgICAgICAgICBpZiAoJGNvdW50IC1sZSAwKSB7IGJyZWFrIH0KICAgICAgICAgICAgICAgICRyZXF1ZXN0LldyaXRlKCRidWZmZXIsIDAsICRjb3VudCkKICAgICAgICAgICAgICAgIGlmIChbVGV4dC5FbmNvZGluZ106OkFTQ0lJLkdldFN0cmluZygkcmVxdWVzdC5Ub0FycmF5KCkpLkNvbnRhaW5zKCJgcmBuYHJgbiIpKSB7IGJyZWFrIH0KICAgICAgICAgICAgfQogICAgICAgICAgICBpZiAoJHJlcXVlc3QuTGVuZ3RoIC1lcSAwIC1vciAkcmVxdWVzdC5MZW5ndGggLWdlIDgxOTIpIHsgY29udGludWUgfQogICAgICAgICAgICAkYnl0ZXMgPSAkcmVxdWVzdC5Ub0FycmF5KCkKICAgICAgICAgICAgJHNlcnZlclN0cmVhbS5Xcml0ZSgkYnl0ZXMsIDAsICRieXRlcy5MZW5ndGgpCiAgICAgICAgICAgICRzZXJ2ZXJTdHJlYW0uRmx1c2goKQogICAgICAgICAgICB3aGlsZSAoJHRydWUpIHsKICAgICAgICAgICAgICAgICRjb3VudCA9ICRzZXJ2ZXJTdHJlYW0uUmVhZCgkYnVmZmVyLCAwLCAkYnVmZmVyLkxlbmd0aCkKICAgICAgICAgICAgICAgIGlmICgkY291bnQgLWxlIDApIHsgYnJlYWsgfQogICAgICAgICAgICAgICAgJHRscy5Xcml0ZSgkYnVmZmVyLCAwLCAkY291bnQpCiAgICAgICAgICAgICAgICAkdGxzLkZsdXNoKCkKICAgICAgICAgICAgfQogICAgICAgIH0gY2F0Y2ggewogICAgICAgICAgICAjIEEgY2xpZW50IGNhbiBkaXNjb25uZWN0IG1pZC1oYW5kc2hha2U7IHRoZSBuZXh0IGNvbm5lY3Rpb24gc3RpbGwgd29ya3MuCiAgICAgICAgfSBmaW5hbGx5IHsKICAgICAgICAgICAgaWYgKCRudWxsIC1uZSAkdXBzdHJlYW0pIHsgJHVwc3RyZWFtLkNsb3NlKCkgfQogICAgICAgICAgICBpZiAoJG51bGwgLW5lICR0bHMpIHsgJHRscy5EaXNwb3NlKCkgfQogICAgICAgICAgICAkY2xpZW50LkNsb3NlKCkKICAgICAgICB9CiAgICB9Cn0gZmluYWxseSB7CiAgICAkbGlzdGVuZXIuU3RvcCgpCn0K'))

$hostPath = Join-Path $configuration 'host'
if (Test-Path -LiteralPath $hostPath) { $hostName = ([IO.File]::ReadAllText($hostPath)).Trim() }
else {
    $hostName = if ($env:VEXPAX2_HOST) { $env:VEXPAX2_HOST.Trim() } else { '127.0.0.1' }
    [IO.File]::WriteAllText($hostPath, $hostName, [Text.Encoding]::ASCII)
}
if ($hostName -notmatch '^[A-Za-z0-9.-]+$') { throw 'Некорректный адрес VEXPAX2_HOST.' }
$key = "vexpax2:v1:${hostName}:18443:${token}:${fingerprint}"
[IO.File]::WriteAllText((Join-Path $configuration 'connection.key'), $key, [Text.Encoding]::ASCII)

& (Join-Path $root 'manage.ps1') start

if ($hostName -ne '127.0.0.1') {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if (-not (Get-NetFirewallRule -DisplayName 'vexpax2 worker port 18443' -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName 'vexpax2 worker port 18443' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 18443 | Out-Null
        }
    } else {
        Write-Warning 'Для удалённого подключения откройте TCP 18443 в Windows Firewall.'
    }
}

$working = $false
for ($attempt = 0; $attempt -lt 8; $attempt++) {
    try {
        $result = Invoke-RestMethod -Uri 'http://127.0.0.1:18787/ping' -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 2
        if ($result.ok -eq $true) { $working = $true; break }
    } catch { Start-Sleep -Milliseconds 500 }
}
if (-not $working) { throw 'Воркер не ответил. Проверьте .\vexpax2\manage.ps1 status.' }

Write-Output ''
Write-Output 'vexpax2 установлен. Вставьте этот ключ в приложение:'
Write-Output $key
Write-Output 'Управление: .\vexpax2\manage.ps1 start|stop|restart|status|key|uninstall'
Write-Output ''

