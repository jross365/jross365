$TargetDrives = (Get-PSDrive -PSProvider FileSystem).Root

$HashTable = @{}

$DuplicateHashes = New-Object System.Collections.ArrayList

$Results = New-Object System.Collections.ArrayList

Foreach ($Drive in $TargetDrives){

$DriveFiles = (Get-ChildItem $Drive -ErrorAction SilentlyContinue).Where({$_.Name -notmatch 'Windows|Program|FileHistory'})
$DriveFiles = ($DriveFiles | Get-ChildItem -File -Recurse -ErrorAction SilentlyContinue).Where({$_.Length -ge 3072}) #Exclude files smaller than 3KB

$x = 1

:ScanFiles Foreach ($File in $DriveFiles){

    Write-Progress -Status "Working on $Drive" -Activity "$x of $($DriveFiles.Count): $($File.Name)" -PercentComplete ([int]($x / $($DriveFiles.Count) * 100))

    $FileHash = Get-FileHash -Path ($File.FullName) -Algorithm SHA256

    Try {$HashTable.Add("$($FileHash.Hash)",@("$($FileHash.Path)"))}

    Catch {

           If ($null -eq $FileHash.Hash){Write-Verbose "Unable to hash file $($File.FullName)" -Verbose; $x++; Continue ScanFiles}

            $DuplicateHashes += "$($FileHash.Hash)"

            $DiscoveredFiles = $HashTable."$($FileHash.Hash)"

            $DiscoveredFiles += ($FileHash.Path)

            $HashTable.Remove("$($FileHash.Hash)")

            $HashTable.Add("$($FileHash.Hash)",$DiscoveredFiles)

          }

    $x++

    }

}

$DuplicateHashes = $DuplicateHashes | Sort-Object -Unique

Foreach ($Hash in $DuplicateHashes){

    $DuplicateFiles = $HashTable.$Hash
    $FileInfo = (Get-Item $DuplicateFiles[0])

    Foreach ($File in $DuplicateFiles){$Results.Add([pscustomobject]@{"SHA256Hash"="$Hash"; "FilePath"=($File); "FileSize(Bytes)"="$($FileInfo.Length)"; "Extension"="$($FileInfo.Extension)" }) | Out-Null}

} #Close foreach Hash

$Results | Export-csv "$($env:USERPROFILE)\Desktop\DuplicateFileReport.csv" -NoTypeInformation