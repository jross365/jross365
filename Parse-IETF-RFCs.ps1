# This script:
 # 1. Scrapes the IETF RFC website,
 # 2. Parses every RFC listing,
 # 3. Correlates all related RFCs and respective datestamps,
 # 4. and exports the results in Gephi-compatible "Node" and "Edge" tables.
 
 Function Convert-NetTimeToGephiTime ($TimeStamp){

$TimeStamp = (Get-date ($TimeStamp) -Format "o")
$TimeStamp = $TimeStamp.Substring(0,($TimeStamp.Length - 5)) + 'Z'

Return $TimeStamp

}

#region 1. Define initial variables:
$RFCIndex = 'https://tools.ietf.org/rfc/index'

$IndexLineBreaks = New-Object System.Collections.ArrayList

$MonthNames = (Get-Culture).DateTimeFormat.MonthGenitiveNames

$Results = New-Object System.Collections.ArrayList

#endregion 1.

#region 2. Pull website data:
$Contents = Invoke-WebRequest -Uri $RFCIndex

#endregion 2.

#region 3. Create RFCs-URLs hashtable for later use:
$LinksHashTable = @{}
$Contents.Links.ForEach({

Try {$LinksHashTable.Add("$($_.outerText)","$($_.href)")}
Catch {} #Suppress duplication errors

})

#endregion 3.

#region 4. Split outerText, trim out "preface" text and align data to "RFC1":
#Split the outer text by Return and NewLine
$SplitContents = $Contents.ParsedHtml.body.outerText -split '\r\n'

#Grab the indexes of all break-lines (""):
(0..$SplitContents.GetUpperBound(0)).ForEach({If ($SplitContents[$_] -eq ""){$IndexLineBreaks += $_}})

#Omit line break indexes leading up to the first RFC ("RFC1"):
$FirstIndex = ($SplitContents.Where{($_[0..4] -join "") -eq 'RFC1 '} | Select-Object -First 1)

#Had to do this in two lines because of the use of quotes to join the characters:
$FirstIndex = $SplitContents.IndexOf("$FirstIndex") 

$IndexLineBreaks = $IndexLineBreaks | ? {$_ -ge ($FirstIndex -1)}

#endregion 4.

#region 5. Build an index table of start and end indexes, using indexes (indexception):
$IndexTable = New-Object System.Collections.ArrayList

(0..($IndexLineBreaks.GetUpperBound(0) - 1)).ForEach({

$IndexTable += ([pscustomobject]@{"StartIndex"=($IndexLineBreaks[$_] + 1); "EndIndex"=($IndexLineBreaks[$_ + 1] - 1)})

})

#endregion 5.

#region 6. Use our index table to "grab" and join lines for each RFC into a single line, each:
$CleanRFCText = New-Object System.Collections.ArrayList

$IndexTable.ForEach({$CleanRFCText += $SplitContents[($_.StartIndex)..($_.EndIndex)].Trim() -join ""})

#endregion 6.

$WorkingOn = 1

#Now let's unintelligently parse out the tidbits:
:RFCLoop Foreach ($RFC in $CleanRFCText){

#region 7. Handle Unissued RFCs:

    If ($RFC -match "Not Issued."){

    $RFCID = $RFC.Split(" ")[0]

    $Results += ([pscustomobject]@{"RFC"=$RFCID;"Title"="Not Issued";"Date"="n/a";"Metadata"="n/a";"Relationships"="None"})
    
    $WorkingOn++

    Continue RFCLoop

    }

#endregion 7.

#region 8. Parse out the RFC ID, Author and Date info:
    #Using the split method and operator because of slightly different behavior with each:
    $InitialSplit = $RFC.Split(' ',2) -split '\. ',2

    #Let's write out where we're at:
    Write-Progress -Activity "Parsing RFC Text" -Status "$($InitialSplit[0])" -PercentComplete ([int](($WorkingOn / $CleanRFCText.Count) * 100))

    #Figure out the gap between the listed date and the author list, by walking-back from the first parenthesis index:
    $FirstParenIndex = $InitialSplit[2].IndexOf('(Format')

    #Now we can delineate author/date strings from status strings and sanitize format:
    $AuthorDateInfo = (($InitialSplit[2][0..($FirstParenIndex -1)] -join '') -replace "\.",'. ' -replace "  "," ").Trim()
    $StatusInfo = $InitialSplit[2][$FirstParenIndex..($InitialSplit[2].Length)] -join ''

    #Fun fact: Many RFC titles don't have a space after the month name. Here's to fix that:
    $MonthNames[0..11].ForEach({$Month = $_; $AuthorDateInfo = $AuthorDateInfo.Replace("$Month","$Month ") -replace "  "," "})

    $x = 0
    
    #If our string ends with a period character, let's cut that out from our starting point:
    If ([int][char]($AuthorDateInfo[$AuthorDateInfo.Length - 1]) -eq 46){$y = $AuthorDateInfo.Length - 2}
    Else {$y = $AuthorDateInfo.Length}
    
    Do {

    #If we match a space or period-mark:
    $CharInt = ([int][char]($AuthorDateInfo[$y]))

    If ($CharInt -eq '32' -or $CharInt -eq '46'){$x++}

    $y--

    }

    Until (($x -eq 2) -or ($y -eq 0))

    #Break Author and Date info out, and trim/clean-up:
    $AuthorInfo = ($AuthorDateInfo[0..$y] -join '').Trim(' \. ')
    $DateInfo = ($AuthorDateInfo[$y..($InitialSplit[2].Length)] -join '').Trim(' \. ')

#endregion 8.

#region 9. Parse out Format, Status, DOI and "Other" (relationship) info:

    $RemoveStrings = New-Object System.Collections.ArrayList
    $SISplit = $StatusInfo.Split('()')
    
    $Format = $SISplit.Where({$_ -match 'Format:'})
    $RemoveStrings += $Format
    $Format = $Format.Split(':')[1].Trim()

    $Status = $SISplit.Where({$_ -match "Status:"})
    $RemoveStrings += $Status
    $Status = $Status.Split(':')[1].Trim()

    $DOI = $SISplit.Where({$_ -match "DOI:"})
    $RemoveStrings += $DOI
    $DOI = $DOI.Split(':')[1].Trim()

    $RemoveStrings.ForEach({$RMStr = $_; $SISplit = $SISplit.Where({$_ -ne $RMStr})})

    $Other = $SISplit.Trim().Where{($_ -ne "" -and $_ -ne " ")}

#endregion 9.

#region 10. Build a "Metadata" PSObject for later use:
    $MetaDataObject = ([pscustomobject]@{"Authors"=$AuthorInfo;"FileFormat"=$Format;"Status"=$Status;"DOICode"=$DOI;"Link"="$($LinksHashTable."$($InitialSplit[0])")"})

#endregion 10.

#region 11. If present, parse and process "Other" (Relationship) data for the RFC:
    If ($Other.Count -eq 0){$Other = ""}
        
    #Break out the "Other" field into its "Obsoletes", "Obsoleted", "Updates", "Updated" RFCs:
    Else {

    $RelObject = New-Object psobject

    #Clean-up formatting and spacing, the lazy/slow/"wrong" way:
    $Other = $Other.Replace('by',''). `
                    Replace('  ',' '). `
                    Replace('Obsoletes','Obsoletes '). `
                    Replace('Obsoleted','Obsoleted '). `
                    Replace('Updates','Updates '). `
                    Replace('Updated','Updated '). `
                    Replace('Also','Also '). `
                    Replace('  ',' ')

        :DocRelLoop Foreach ($Relationship in $Other){
        
        #Now let's split/parse the data:
        $LineSplit = $Relationship.Split(', ')
        $Rel = $LineSplit[0]
        $RelDocs = $LineSplit[1..($LineSplit.GetUpperBound(0))].Where({$_ -ne " " -and $_ -ne ""})
        Switch ($Rel){

        {$_ -match "Also"}{ Continue DocRelLoop} #Skip "Also" line entries, since "also" has ambiguous meaning in these listings

        {$_ -match "Obsoletes"}{$Propertyname = "Obsoletes";}

        {$_ -match "Obsoleted"}{$PropertyName = "ObsoletedBy";}

        {$_ -match "Updates"}{$Propertyname = "Updates"}

        {$_ -match "Updated"}{$Propertyname = "UpdatedBy"}

        } #Close switch $Rel

        Try {$RelObject | Add-Member -MemberType NoteProperty -Name "$PropertyName" -Value ($RelDocs) -ErrorAction Stop}
        Catch {Write-host "$($InitialSplit[0])"; $RelObject | Format-List}

        }


    } #Close Else Count -ne 0    

#endregion 11.

#region 12. Append our "master" object to $Results and increment our status counter:
    $Results += ([pscustomobject]@{"RFC"=$InitialSplit[0];"Title"=$InitialSplit[1];"Date"=$DateInfo;"Metadata"=$MetaDataObject;"Relationships"=$RelObject})

    $WorkingOn++

}

#endregion 12.

#region 13. Export our results as JSON:
$Results | ConvertTo-Json | Out-File "RFCs_Info.json"

#endregion 13.

#region 14. Build Gephi Nodes Table

$NodeHashTable = @{}
$NodeRecordTable = New-Object System.Collections.ArrayList

$x = 1

$Results.Where({$_.Title -ne "Not Issued"}).ForEach({

#This converts "RFC10" to "RFC0010", for example:
$PaddedRFCName = "RFC" + "$('{0:d4}' -f [int]("$($_.RFC)" -replace 'RFC',''))"

$NodeDate = Convert-NetTimeToGephiTime -TimeStamp ($_.Date)

$NodeHashTable.Add("$PaddedRFCName",([pscustomobject]@{"id"=$x; "date"="$NodeDate"}))

$NodeRecordTable += [pscustomobject]@{"Id"=$x;"Label"="$PaddedRFCName";"Timeset"="$NodeDate";"Type"="Directed";"Status"="$($_.Metadata.Status)"}

$x++

})

#endregion 14.

#region 15. Compute Gephi Edges Table

$EdgeRecordTable = New-Object System.Collections.ArrayList

$RelationshipFields = @("Obsoletes","ObsoletedBy","Updates","UpdatedBy")

$Results.Where({$_.Title -ne "Not Issued"}).ForEach({

#$Entry = #This converts "RFC10" to "RFC0010", for example:
$Entry = "RFC" + "$('{0:d4}' -f [int]("$($_.RFC)" -replace 'RFC',''))"

$EntryLookup = $NodeHashTable."$Entry"
$EntryId = $EntryLookup.id
$EntryDate = $EntryLookup.date
$Relationships = $_.Relationships

#Let's use modulus and the RelationshipFields indexes to determine source/target order
$EntryRelFields = $Relationships.psobject.Members.Where({$_.MemberType -eq "NoteProperty"}).Name

If ($EntryRelFields -ne $Null){
    
   $EntryRelFields.ForEach({
    
    $Field = $_ #And to cut down on token confusion

    switch (($RelationshipFields.IndexOf("$Field")) % 2){

    0 { #Mod2 = zero is even: "Obsoletes", "Updates"
    
        $SourceId = $EntryId 
        $EdgeTime = $EntryDate

        $Relationships.$Field.Foreach({
            
            $TargetRFC = $_ #Again, to cut down on token confusion
            $TargetId = $NodeHashTable."$TargetRFC".id

            $EdgeRecordTable += [pscustomobject]@{"Source"="$SourceId";"Target"="$TargetId";"Timeset"="$EdgeTime";"Relationship"="$Field"}

            }) #Close $Relationships.$Field.Foreach
      } #Close Switch (0)

    1 { #Mod2 = one is odd: "ObsoletedBy", "UpdatedBy"
    
        $TargetId = $EntryId

        $RelationShips.$Field.Foreach({

        $SourceRFC = $_ #Once again, to cut down on token confusion
        $SourceData = $NodeHashTable."$SourceRFC"
        $SourceId = $SourceData.id
        $EdgeTime = $SourceData.date

        $EdgeRecordTable += [pscustomobject]@{"Source"="$SourceId";"Target"="$TargetId";"Timeset"="$EdgeTime";"Relationship"="$Field"}

        }) #Close $Relationships.$Field.Foreach
    
      } #Close Switch (1)

    } #Close Switch

    })

}  #Close if $EntryRelFields -ne $null

})

#endregion 15.

#region 16. Filter out all external document references in the edges table, and export our data:

$NodeRecordTable | Export-csv "Nodes.csv" -NoTypeInformation

$EdgeRecordTable.Where({$_.Source -ne "" -and $_.Target -ne ""}) | Export-csv "Edges.csv" -NoTypeInformation

#endregion 16.
