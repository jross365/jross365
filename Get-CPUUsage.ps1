Function Three-Chars ($Value){
    $N = 1..2

    If ([bool]($N -match ([string]$Value).Length)){
        
            $Y = ""
            (1..(3 - ([string]$Value).Length)).ForEach({$Y += " "})
            $Y += [string]$Value
        
            Return $Y
          
         } #Close If
         
    Else {Return $Value}

} #Close function

Function Get-CPUUsage {

If ($null -eq $Global:CPUParams){

    $Global:CPUParams = @{}

    $Global:CPUParams.Add("Cores",(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors)

#region 0. Identify preferred X/Y Grid mapping

    $SqRt = [system.math]::Sqrt($Global:CPUCores)

    If ($SqRt.GetType().Name -match "Int"){
    
            $Global:CPUParams.Add("X",$SqRt)
            $Global:CPUParams.Add("Y",$SqRt)

            } #Close if square root
    Else {

    $CoordTest = New-Object System.Collections.ArrayList
    $UpperLimit = ([system.math]::Ceiling([system.math]::Sqrt($Global:CPUParams.Cores))) * 2

    (2..$UpperLimit).ForEach({$CoordTest.Add([pscustomobject]@{"X"=$_; "Y"=($Global:CPUParams.Cores / $_); "Diff"=($null)}) | Out-Null})
    
    $CoordTest.ForEach({$_.Diff = [System.Math]::abs(($_.X - $_.Y))})
    $CoordTest = $CoordTest.Where({[string]($_.Diff) -notmatch '\.'}) | Sort-Object Diff

    $ChosenCoords = $CoordTest.Where({$_.Diff -eq ($CoordTest[0].Diff) -and ($_.X -ge $_.Y)})

    Try {$Global:CPUParams.Add("X",($ChosenCoords.X))}
    Catch {$Global:CPUParams.'X' = $ChosenCoords.X}
    
    Try {$Global:CPUParams.Add("Y",($ChosenCoords.Y))}
    Catch {$Global:CPUParams.'Y' = $ChosenCoords.Y}

    } #Close Else

} #Close If $null eq $Global:CPUParams

#endregion 0.

#region 1. Build output template
$ExecutionTemplate = New-Object System.Collections.ArrayList

$BaseString = 'Write-Host "[CC]" -ForegroundColor FG -BackgroundColor BG -NoNewLine; '

$CoreCounter = 0

$CoreRowHash = @{}

(0..($Global:CPUParams.Y - 1)).ForEach({

$Row = $_

$LineString = ""

    (0..($Global:CPUParams.X - 1)).ForEach({

    $Column = $_

    $ReplString = $BaseString -replace 'CC',"CC$($CoreCounter)" -replace 'FG',"FG$($CoreCounter)" -replace 'BG',"BG$($CoreCounter)"

    If ($Column -eq ($Global:CPUParams.X - 1)){$ReplString = $ReplString -replace '-NoNewLine',''}

    $LineString += $ReplString

    $CoreRowHash.Add($CoreCounter,$Row)

    $CoreCounter++

    }) #Close X

$ExecutionTemplate.Add($LineString) | Out-Null

}) #Close Y

#endregion 1.

#region 2. Build %/Color Hash Table
$ColorHash = @{}

(0..2).ForEach({$ColorHash.Add($_,[pscustomobject]@{"FG"="DarkCyan";"BG"="Cyan"})})
(3..49).ForEach({$ColorHash.Add($_,[pscustomobject]@{"FG"="DarkGreen";"BG"="Green"})})
(50..79).ForEach({$ColorHash.Add($_,[pscustomobject]@{"FG"="DarkYellow";"BG"="Yellow"})})
(80..99).ForEach({$ColorHash.Add($_,[pscustomobject]@{"FG"="DarkRed";"BG"="Red"})})
$ColorHash.Add(100,[pscustomobject]@{"FG"="White";"BG"="Red"})

#endregion 2.

#region 3. Put it all together
Do {

$Cores = (Get-WmiObject -Query "SELECT Name, PercentProcessorTime FROM Win32_PerfFormattedData_PerfOS_Processor WHERE NOT Name LIKE '_Total'") | Select-Object Name,PercentProcessorTime,@{N="PercentAsString";E={Three-Chars -Value ($_.PercentProcessorTime)}}

$ExecutionStrings = New-Object System.Collections.ArrayList

$ExecutionTemplate.ForEach({$ExecutionStrings.Add($_)})

$Cores.ForEach({
 
 $C = $_
 [int]$CID = $C.Name

 $CoreLine = $CoreRowHash.($CID)
 $CoreColors = $ColorHash.[int]($C.PercentProcessorTime)

 $CoreUsedString = 'CC' + "$($CID)"
 $CoreFGString = 'FG' + "$($CID)"
 $CoreBGString = 'BG' + "$($CID)"

 $ExecutionStrings[$CoreLine] = $ExecutionStrings[$CoreLine] -replace "$CoreUsedString","$($C.PercentAsString)"
 $ExecutionStrings[$CoreLine] = $ExecutionStrings[$CoreLine] -replace "$CoreFGString","$($CoreColors.FG)"
 $ExecutionStrings[$CoreLine] = $ExecutionStrings[$CoreLine] -replace "$CoreBGString","$($CoreColors.BG)"

 }) #Close Cores.ForEach

Clear-Host

$ExecutionStrings.ForEach({Invoke-Expression $_})

Start-Sleep -Milliseconds 500

} #Close Do
Until ($null -eq $Cores)

#endregion 3.

} #Close Function


