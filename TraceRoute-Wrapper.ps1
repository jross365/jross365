#This script contains a function that's a wrapper for tracert (traceroute)
 
 function Trace-Route ($Destination){

$LASTEXITCODE = $null

Set-Alias traceroute "$($env:windir)\system32\tracert.exe"

$TraceRouteResults = New-Object System.Collections.ArrayList

$TraceRouteData = traceroute $Destination

If ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null){throw "traceroute returned LastExitCode $LASTEXITCODE"}

Else {

[regex]$Brackets = '\[|\]'

$TraceRouteData = $TraceRouteData -split '\r\n'

$StartIndex = 4

$EndIndex = $TraceRouteData.Count - 3

ForEach ($Hop in ($TraceRouteData[$StartIndex..$EndIndex])){

    $HopSplit = ($Hop -split '  ').Where({$_ -ne ""}).Trim()

    $Device = $HopSplit[4] -split ' '
    
    Switch ($Device.Count){

    1 {
    
    $DevName = ""
    $DevIP = $Device[0] -replace $Brackets
    
    } #Close 1

    2 {
    
    $DevName = $Device[0]
    $DevIP = $Device[1] -replace $Brackets
    
    } #Close 2

    } #Close Switch 


    $TraceRouteResults.Add(

    [pscustomobject]@{

        "Hop"="$($HopSplit[0])";
        "RTT1"="$($HopSplit[1])";
        "RTT2"="$($HopSplit[2])";
        "RTT3"="$($HopSplit[3])";
        "Hostname"="$DevName";
        "IPAddress"="$DevIP"
        
        } #Close PSCustomObject

    ) | Out-Null

    } #Close Foreach
    
    return $TraceRouteResults

} #CLose Else

} #Close function TraceRoute
