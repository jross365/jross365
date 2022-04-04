# This script scrapes public blocklists and imports them into a Windows system's HOSTS file as 127.0.0.1
  
 $Root = "https://isc.sans.edu"
$MalwareDomains = "http://mirror1.malwaredomains.com/files/domains.txt"
$RansomwareDomains = "https://ransomwaretracker.abuse.ch/downloads/RW_DOMBL.txt"
$ZeusDomains = "https://zeustracker.abuse.ch/blocklist.php?download=domainblocklist"
$RJMBlacklist = "https://www.rjmblocklist.com/free/badips.txt"

$HostsFile = $env:SystemRoot + '\System32\Drivers\etc\hosts'

$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

$Domains = New-Object System.Collections.ArrayList
$IPs = New-Object System.Collections.ArrayList

Try {Get-Content $HostsFile -ErrorAction SilentlyContinue | Set-Content $HostsFile -ErrorAction SilentlyContinue}
Catch {throw "Unable to write to the host file at $HostsFile. Please run this as an Administrator"; break}

Try {$Feeds = (Invoke-WebRequest "$($Root + "/suspicious_domains.html")" -ErrorAction Stop).RawContent.Split("`r`n") | ? {$_ -match "suspiciousdomains" -and $_ -notmatch "whitelist"}}
Catch  {Throw "Unable to retrieve sans.edu blackhole list URLs";}

$DomainFiles = $Feeds | % {($_ -split 'href="') -split '">' | ? {$_ -match ".txt"}}

#Let's get suspicious domain entries from isc.sans.edu
Foreach ($File in $DomainFiles){

Try {$Text = ((Invoke-WebRequest "$($Root + $File)" -ErrorAction Stop).RawContent).Split("`r`n") | ? {$_ -ne ""}}
Catch {Throw "Unable to retrieve sans.edu suspicious domains entries"; break}

$Start = $Text.IndexOf("Site") + 1
$End = $Text.IndexOf("# STATISTICS") - 1
$Domains += $Text[$Start..$End]

} #Close foreach domain

$Failed = $False

#Now let's get the domains from malwaredomains.com:
Try {Invoke-WebRequest -Uri $MalwareDomains -OutFile "domains.txt" -ErrorAction Stop}
Catch {Throw "Unable to get domains from $MalwareDomains"}

$MalwareDomains = Get-Content domains.txt | ? {$_ -notmatch "#"}

Foreach ($Entry in $MalwareDomains){

$D = ($Entry -split "	")[2]

If ($D -ne $Null){$Domains += $D}

} #Close foreach entry 

#Now let's get the ransomware domains
Try {Invoke-WebRequest -Uri $RansomwareDomains -OutFile "domains.txt" -ErrorAction Stop}
Catch {Throw "Unable to get domains from $RansomwareDomains"}

$RansomwareDomains = Get-Content .\domains.txt | ? {$_ -notmatch "#"}

$Domains += $RansomwareDomains


#Now let's get the Zeus domains
Try {Invoke-WebRequest -Uri $ZeusDomains -OutFile "domains.txt" -ErrorAction Stop}
Catch {Throw "Unable to get domains from $ZeusDomains"}

$ZeusDomains = Get-Content .\domains.txt | ? {$_ -notmatch "#"}

$Domains += $ZeusDomains

Remove-Item domains.txt -ErrorAction SilentlyContinue

#Normalize/clean up the list
$Domains = $Domains | Sort-Object -Unique | ? {$_.Length -gt 3}

$x = 1

#Let's try to resolve and create a list of miscreant IPs
:DomainsLoop Foreach ($Domain in $Domains){
Write-Progress -Activity "Resolving domains" -Status "Working on $Domain" -PercentComplete ([int](($x / $Domains.Count) * 100))

Try {$IPs += ([system.net.dns]::GetHostAddresses($Domain)).IPAddressToString}
Catch {}

$x++

} #Close foreach domain

#Export the reverse lookup results, excluding those that resolve as localhost because of hosts file updates:
$IPs | Sort-Object -Unique | ? {$_ -ne "127.0.0.1"} | Set-Content "BadIPs.txt" 

Try {$FileContent = Get-Content $HostsFile -ErrorAction stop}
Catch {Throw "Unable to read Hosts file"; break}

$BlackholeHeader = "#Begin Blackhole Entries"

If ($FileContent -match $BlackholeHeader){

$MarkerIndex = $FileContent.IndexOf($BlackholeHeader)
$FileContent = $FileContent[0..$MarkerIndex]

} #Close if hosts file matches the header

else {$FileContent += "$BlackholeHeader"}

Foreach ($Domain in $Domains){

$AppendString = "`t" + "127.0.0.1" + "`t" + "$Domain"
$FileContent += $AppendString

} #Close foreach domain

Try {$FileContent | Set-Content -Path $HostsFile -ErrorAction Stop}
Catch {Throw "Unable to write blackhole entries to Hosts file"; break}

