$ErrorActionPreference='Stop'
if(-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter SDK not found in PATH. Install Flutter and Android SDK / Visual Studio C++ tools first.' }
Set-Location $PSScriptRoot
flutter create --platforms=android,windows --project-name easy_authenticator .
if($LASTEXITCODE -ne 0){throw 'flutter create failed'}
$manifest='android\app\src\main\AndroidManifest.xml'
$xml=Get-Content $manifest -Raw
if($xml -notmatch 'android.permission.CAMERA'){$xml=$xml -replace '<application','<uses-permission android:name="android.permission.CAMERA"/><application';Set-Content $manifest $xml}
flutter pub get
if($LASTEXITCODE -ne 0){throw 'flutter pub get failed'}
Write-Host 'Project initialized. Run flutter run -d windows or flutter run -d android.' -ForegroundColor Green
