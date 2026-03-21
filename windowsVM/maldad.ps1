$bytes = [byte[]](,0xFF * (6 * 1MB))
[System.IO.File]::WriteAllBytes("C:\Perfiles\sdiaz\test.bin", $bytes)