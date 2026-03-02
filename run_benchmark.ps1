Write-Host "Benchmarking Vector Addition"
Write-Host "---------------------------------------------------"
Write-Host "Threads/Block | Total Kernel Time (ms)"
Write-Host "---------------------------------------------------"


$executable = ".\x64\Release\large-vector-addition.exe" 

for ($i = 32; $i -le 1024; $i *= 2) {
    & $executable $i
}