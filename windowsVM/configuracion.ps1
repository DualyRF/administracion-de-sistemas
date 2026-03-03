# Resetear contrasena de chicle
$pwd = ConvertTo-SecureString "Chicle@2026" -AsPlainText -Force
Set-LocalUser -Name "chicle" -Password $pwd