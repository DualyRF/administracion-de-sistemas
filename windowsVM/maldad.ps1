$passSegura = ConvertTo-SecureString "SafeModeP@ss123!" -AsPlainText -Force

Install-ADDSForest `
    -DomainName "empresa.local" `
    -DomainNetBiosName "EMPRESA" `
    -InstallDns $true `
    -SafeModeAdministratorPassword $passSegura `
    -Force