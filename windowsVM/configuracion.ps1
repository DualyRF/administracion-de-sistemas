Import-Module WebAdministration

Set-ItemProperty "IIS:\Sites\MiFTP" `
    -Name "ftpServer.security.ssl.controlChannelPolicy" -Value 0

Set-ItemProperty "IIS:\Sites\MiFTP" `
    -Name "ftpServer.security.ssl.dataChannelPolicy" -Value 0

Stop-Service ftpsvc -Force
Start-Sleep -Seconds 2
Start-Service ftpsvc

& "$env:SystemRoot\System32\inetsrv\appcmd.exe" start site MiFTP
Write-Host "Listo" -ForegroundColor Green