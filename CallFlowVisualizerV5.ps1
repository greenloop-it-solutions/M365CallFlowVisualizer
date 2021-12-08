

function Select-AutoAttendantsAndCallQueues {
    param (
        [Parameter(Mandatory=$false)][String]$VoiceAppId
    )

    if ($VoiceAppId) {

        try {
            $VoiceApp = Get-CsAutoAttendant -Identity $VoiceAppId
            $VoiceAppType = "AutoAttendant"
        }
        catch {
            $VoiceApp = Get-CsCallQueue -Identity $VoiceAppId
            $VoiceAppType = "CallQueue"
        }
        finally {
            Write-Host $VoiceApp.Name
            Write-Host $VoiceAppType
        }

    }

    else {

        $TenantAutoAttendants = (Get-CsAutoAttendant | Select-Object Name, Identity)
        $TenantCallQueues = (Get-CsCallQueue | Select-Object Name, Identity)

        $VoiceAppId = (($TenantAutoAttendants += $TenantCallQueues) | Out-GridView -Title "Please choose an auto attendant or a call queue from the list." -PassThru).Identity

        try {
            $VoiceApp = Get-CsAutoAttendant -Identity $VoiceAppId
            $VoiceAppType = "AutoAttendant"
        }
        catch {
            $VoiceApp = Get-CsCallQueue -Identity $VoiceAppId
            $VoiceAppType = "CallQueue"
        }
        finally {
            Write-Host $VoiceApp.Name
            Write-Host $VoiceAppType
        }

    }

}


function Find-Holidays {
    param (
        [Parameter(Mandatory=$true)][String]$VoiceAppId

    )

    $aa = Get-CsAutoAttendant -Identity $VoiceAppId

    if ($aa.CallHandlingAssociations.Type.Value -contains "Holiday") {
        $aaHasHolidays = $true    
    }

    else {
        $aaHasHolidays = $false
    }
    
}

function Find-AfterHours {
    param (
        [Parameter(Mandatory=$true)][String]$VoiceAppId

    )

    $aa = Get-CsAutoAttendant -Identity $VoiceAppId

    # Create ps object which has no business hours, needed to check if it matches an auto attendants after hours schedule
    $aaDefaultScheduleProperties = New-Object -TypeName psobject

    $aaDefaultScheduleProperties | Add-Member -MemberType NoteProperty -Name "ComplementEnabled" -Value $true
    $aaDefaultScheduleProperties | Add-Member -MemberType NoteProperty -Name "MondayHours" -Value "00:00:00-1.00:00:00"
    $aaDefaultScheduleProperties | Add-Member -MemberType NoteProperty -Name "TuesdayHours" -Value "00:00:00-1.00:00:00"
    $aaDefaultScheduleProperties | Add-Member -MemberType NoteProperty -Name "WednesdayHours" -Value "00:00:00-1.00:00:00"
    $aaDefaultScheduleProperties | Add-Member -MemberType NoteProperty -Name "ThursdayHours" -Value "00:00:00-1.00:00:00"
    $aaDefaultScheduleProperties | Add-Member -MemberType NoteProperty -Name "FridayHours" -Value "00:00:00-1.00:00:00"
    $aaDefaultScheduleProperties | Add-Member -MemberType NoteProperty -Name "SaturdayHours" -Value "00:00:00-1.00:00:00"
    $aaDefaultScheduleProperties | Add-Member -MemberType NoteProperty -Name "SundayHours" -Value "00:00:00-1.00:00:00"

    # Convert to string for comparison
    $aaDefaultScheduleProperties = $aaDefaultScheduleProperties | Out-String
    
    # Get the current auto attendants after hours schedule and convert to string
    $aaAfterHoursScheduleProperties = ($aa.Schedules | Where-Object {$_.name -match "after"}).WeeklyRecurrentSchedule | Out-String

    # Check if the auto attendant has business hours by comparing the ps object to the actual config of the current auto attendant
    if ($aaDefaultScheduleProperties -eq $aaAfterHoursScheduleProperties) {
        $aaHasAfterHours = $false
    }

    else {
        $aaHasAfterHours = $true
    }
    
}

function Get-AutoAttendantHolidaysAndAfterHours {
    param (
        [Parameter(Mandatory=$true)][String]$VoiceAppId,
        [Parameter(Mandatory=$false)][Bool]$InvokedByNesting = $false,
        [Parameter(Mandatory=$false)][String]$NestedAaCallFlowType
    )

    if (!$aaCounter) {
        $aaCounter = 0
    }

    $aaCounter ++

    if ($aaHasHolidays -eq $true) {

        # The counter is here so that each element is unique in Mermaid
        $HolidayCounter = 1

        # Create empty mermaid subgraph for holidays
        $mdSubGraphHolidays =@"
subgraph Holidays-$($aaCounter)
    direction LR
"@

        $aaHolidays = $aa.CallHandlingAssociations | Where-Object {$_.Type -match "Holiday" -and $_.Enabled -eq $true}

        foreach ($HolidayCallHandling in $aaHolidays) {

            $holidayCallFlow = $aa.CallFlows | Where-Object {$_.Id -eq $HolidayCallHandling.CallFlowId}
            $holidaySchedule = $aa.Schedules | Where-Object {$_.Id -eq $HolidayCallHandling.ScheduleId}

            if (!$holidayCallFlow.Greetings) {

                $holidayGreeting = "Greeting <br> None"

            }

            else {

                $holidayGreeting = "Greeting <br> $($holidayCallFlow.Greetings.ActiveType.Value)"

            }

            $holidayAction = $holidayCallFlow.Menu.MenuOptions.Action.Value

            # Check if holiday call handling is disconnect call
            if ($holidayAction -eq "DisconnectCall") {

                $nodeElementHolidayAction = "elementAAHolidayAction$($aaCounter)-$($HolidayCounter)(($holidayAction))"

            }

            else {

                $holidayActionTargetType = $holidayCallFlow.Menu.MenuOptions.CallTarget.Type.Value

                # Switch through different transfer call to target types
                switch ($holidayActionTargetType) {
                    User { $holidayActionTargetTypeFriendly = "User" 
                    $holidayActionTargetName = (Get-MsolUser -ObjectId $($holidayCallFlow.Menu.MenuOptions.CallTarget.Id)).DisplayName
                }
                    SharedVoicemail { $holidayActionTargetTypeFriendly = "Voicemail"
                    $holidayActionTargetName = (Get-MsolGroup -ObjectId $($holidayCallFlow.Menu.MenuOptions.CallTarget.Id)).DisplayName
                }
                    ExternalPstn { $holidayActionTargetTypeFriendly = "External Number" 
                    $holidayActionTargetName =  ($holidayCallFlow.Menu.MenuOptions.CallTarget.Id).Replace("tel:","")
                }
                    # Check if the application endpoint is an auto attendant or a call queue
                    ApplicationEndpoint {                    
                    $MatchingAA = Get-CsAutoAttendant | Where-Object {$_.ApplicationInstances -eq $holidayCallFlow.Menu.MenuOptions.CallTarget.Id}

                        if ($MatchingAA) {

                            $holidayActionTargetTypeFriendly = "[Auto Attendant"
                            $holidayActionTargetName = "$($MatchingAA.Name)]"

                        }

                        else {

                            $MatchingCQ = Get-CsCallQueue | Where-Object {$_.ApplicationInstances -eq $holidayCallFlow.Menu.MenuOptions.CallTarget.Id}

                            $holidayActionTargetTypeFriendly = "[Call Queue"
                            $holidayActionTargetName = "$($MatchingCQ.Name)]"

                        }

                    }
                
                }

                # Create mermaid code for the holiday action node based on the variables created in the switch statemenet
                $nodeElementHolidayAction = "elementAAHolidayAction$($aaCounter)-$($HolidayCounter)($holidayAction) --> elementAAHolidayActionTargetType$($aaCounter)-$($HolidayCounter)($holidayActionTargetTypeFriendly <br> $holidayActionTargetName)"

            }

            # Create subgraph per holiday call handling inside the Holidays subgraph
            $nodeElementHolidayDetails =@"

subgraph $($holidayCallFlow.Name)
direction LR
elementAAHoliday$($aaCounter)-$($HolidayCounter)(Schedule <br> $($holidaySchedule.FixedSchedule.DateTimeRanges.Start) <br> $($holidaySchedule.FixedSchedule.DateTimeRanges.End)) --> elementAAHolidayGreeting$($aaCounter)-$($HolidayCounter)>$holidayGreeting] --> $nodeElementHolidayAction
    end
"@

            # Increase the counter by 1
            $HolidayCounter ++

            # Add holiday call handling subgraph to holiday subgraph
            $mdSubGraphHolidays += $nodeElementHolidayDetails

        } # End of for-each loop

        # Create end for the holiday subgraph
        $mdSubGraphHolidaysEnd =@"

    end
"@
            
        # Add the end to the holiday subgraph mermaid code
        $mdSubGraphHolidays += $mdSubGraphHolidaysEnd

        # Mermaid node holiday check
        $nodeElementHolidayCheck = "elementHolidayCheck$($aaCounter){During Holiday?}"
    } # End if aa has holidays

    # Check if auto attendant has after hours and holidays
    if ($aaHasAfterHours) {

        # Get the business hours schedule and convert to csv for comparison with hard coded strings
        $aaBusinessHours = ($aa.Schedules | Where-Object {$_.name -match "after"}).WeeklyRecurrentSchedule | ConvertTo-Csv

        # Convert from csv to read the business hours per day
        $aaBusinessHoursFriendly = $aaBusinessHours | ConvertFrom-Csv

        $aaTimeZone = $aa.TimeZoneId

        # Monday
        # Check if Monday has business hours which are open 24 hours per day
        if ($aaBusinessHoursFriendly.DisplayMondayHours -eq "00:00:00-1.00:00:00") {
            $mondayHours = "Monday Hours: Open 24 hours"
        }
        # Check if Monday has business hours set different than 24 hours open per day
        elseif ($aaBusinessHoursFriendly.DisplayMondayHours) {
            $mondayHours = "Monday Hours: $($aaBusinessHoursFriendly.DisplayMondayHours)"
        }
        # Check if Monday has no business hours at all / is closed 24 hours per day
        else {
            $mondayHours = "Monday Hours: Closed"
        }

        # Tuesday
        if ($aaBusinessHoursFriendly.DisplayTuesdayHours -eq "00:00:00-1.00:00:00") {
            $TuesdayHours = "Tuesday Hours: Open 24 hours"
        }
        elseif ($aaBusinessHoursFriendly.DisplayTuesdayHours) {
            $TuesdayHours = "Tuesday Hours: $($aaBusinessHoursFriendly.DisplayTuesdayHours)"
        } 
        else {
            $TuesdayHours = "Tuesday Hours: Closed"
        }

        # Wednesday
        if ($aaBusinessHoursFriendly.DisplayWednesdayHours -eq "00:00:00-1.00:00:00") {
            $WednesdayHours = "Wednesday Hours: Open 24 hours"
        } 
        elseif ($aaBusinessHoursFriendly.DisplayWednesdayHours) {
            $WednesdayHours = "Wednesday Hours: $($aaBusinessHoursFriendly.DisplayWednesdayHours)"
        }
        else {
            $WednesdayHours = "Wednesday Hours: Closed"
        }

        # Thursday
        if ($aaBusinessHoursFriendly.DisplayThursdayHours -eq "00:00:00-1.00:00:00") {
            $ThursdayHours = "Thursday Hours: Open 24 hours"
        } 
        elseif ($aaBusinessHoursFriendly.DisplayThursdayHours) {
            $ThursdayHours = "Thursday Hours: $($aaBusinessHoursFriendly.DisplayThursdayHours)"
        }
        else {
            $ThursdayHours = "Thursday Hours: Closed"
        }

        # Friday
        if ($aaBusinessHoursFriendly.DisplayFridayHours -eq "00:00:00-1.00:00:00") {
            $FridayHours = "Friday Hours: Open 24 hours"
        } 
        elseif ($aaBusinessHoursFriendly.DisplayFridayHours) {
            $FridayHours = "Friday Hours: $($aaBusinessHoursFriendly.DisplayFridayHours)"
        }
        else {
            $FridayHours = "Friday Hours: Closed"
        }

        # Saturday
        if ($aaBusinessHoursFriendly.DisplaySaturdayHours -eq "00:00:00-1.00:00:00") {
            $SaturdayHours = "Saturday Hours: Open 24 hours"
        } 

        elseif ($aaBusinessHoursFriendly.DisplaySaturdayHours) {
            $SaturdayHours = "Saturday Hours: $($aaBusinessHoursFriendly.DisplaySaturdayHours)"
        }

        else {
            $SaturdayHours = "Saturday Hours: Closed"
        }

        # Sunday
        if ($aaBusinessHoursFriendly.DisplaySundayHours -eq "00:00:00-1.00:00:00") {
            $SundayHours = "Sunday Hours: Open 24 hours"
        }
        elseif ($aaBusinessHoursFriendly.DisplaySundayHours) {
            $SundayHours = "Sunday Hours: $($aaBusinessHoursFriendly.DisplaySundayHours)"
        }

        else {
            $SundayHours = "Sunday Hours: Closed"
        }

        # Create the mermaid node for business hours check including the actual business hours
        $nodeElementAfterHoursCheck = "elementAfterHoursCheck$($aaCounter){During Business Hours? <br> Time Zone: $aaTimeZone <br> $mondayHours <br> $tuesdayHours  <br> $wednesdayHours  <br> $thursdayHours <br> $fridayHours <br> $saturdayHours <br> $sundayHours}"

    } # End if aa has after hours

    if ($aaHasHolidays -eq $true) {

        if ($aaHasAfterHours) {

            $mdHolidayAndAfterHoursCheck =@"
--> $nodeElementHolidayCheck
$nodeElementHolidayCheck -->|Yes| Holidays-$($aaCounter)
$nodeElementHolidayCheck -->|No| $nodeElementAfterHoursCheck
$nodeElementAfterHoursCheck -->|No| $mdAutoAttendantAfterHoursCallFlow
$nodeElementAfterHoursCheck -->|Yes| $mdAutoAttendantDefaultCallFlow

$mdSubGraphHolidays

"@
        }

        else {
            $mdHolidayAndAfterHoursCheck =@"
--> $nodeElementHolidayCheck
$nodeElementHolidayCheck -->|Yes| Holidays-$($aaCounter)
$nodeElementHolidayCheck -->|No| $mdAutoAttendantDefaultCallFlow

$mdSubGraphHolidays

"@
        }

    }

    
    # Check if auto attendant has no Holidays but after hours
    else {
    
        if ($aaHasAfterHours -eq $true) {

            $mdHolidayAndAfterHoursCheck =@"
--> $nodeElementAfterHoursCheckCheck
$nodeElementAfterHoursCheck -->|No| $mdAutoAttendantAfterHoursCallFlow
$nodeElementAfterHoursCheck -->|Yes| $mdAutoAttendantDefaultCallFlow


"@      
        }

        # Check if auto attendant has no after hours and no holidays
        else {

            $mdHolidayAndAfterHoursCheck =@"
--> $mdAutoAttendantDefaultCallFlow

"@
        }

    
    }

    if ($InvokedByNesting -eq $false) {
        $mdInitialHolidayAndAfterHoursCheck = $mdHolidayAndAfterHoursCheck
    }

    else {

        if ($NestedAaCallFlowType -eq "Default") {
            $mdNestedAaDefaultCallFlowHolidayAndAfterHoursCheck = $mdHolidayAndAfterHoursCheck
        }
        elseif ($NestedAaCallFlowType -eq "AfterHours") {
            $mdNestedAaAfterHoursCallFlowHolidayAndAfterHoursCheck = "afterHoursCallFlowAction1 " + $mdHolidayAndAfterHoursCheck
        }
        else {
            $mdNestedAaDefaultCallFlowHolidayAndAfterHoursCheck = $null
            $mdNestedAaAfterHoursCallFlowHolidayAndAfterHoursCheck = $null
        }
    }

}

function Get-AutoAttendantDefaultCallFlow {
    param (
        [Parameter(Mandatory=$false)][String]$VoiceAppId,
        [Parameter(Mandatory=$false)][Bool]$InvokedByNesting = $false,
        [Parameter(Mandatory=$false)][String]$NestedAaCallFlowType
    )

    if (!$aaDefaultCallFlowCounter) {
        $aaDefaultCallFlowCounter = 0
    }

    $aaDefaultCallFlowCounter ++

    # Get the current auto attendants default call flow and default call flow action
    $defaultCallFlow = $aa.DefaultCallFlow
    $defaultCallFlowAction = $aa.DefaultCallFlow.Menu.MenuOptions.Action.Value

    # Get the current auto attentans default call flow greeting
    if (!$defaultCallFlow.Greetings.ActiveType.Value){
        $defaultCallFlowGreeting = "Greeting <br> None"
    }

    else {
        $defaultCallFlowGreeting = "Greeting <br> $($defaultCallFlow.Greetings.ActiveType.Value)"
    }

    # Check if the default callflow action is transfer call to target
    if ($defaultCallFlowAction -eq "TransferCallToTarget") {

        # Get transfer target type
        $defaultCallFlowTargetType = $aa.DefaultCallFlow.Menu.MenuOptions.CallTarget.Type.Value

        # Switch through transfer target type and set variables accordingly
        switch ($defaultCallFlowTargetType) {
            User { 
                $defaultCallFlowTargetTypeFriendly = "User"
                $defaultCallFlowTargetName = (Get-MsolUser -ObjectId $($aa.DefaultCallFlow.Menu.MenuOptions.CallTarget.Id)).DisplayName}
            ExternalPstn { 
                $defaultCallFlowTargetTypeFriendly = "External PSTN"
                $defaultCallFlowTargetName = ($aa.DefaultCallFlow.Menu.MenuOptions.CallTarget.Id).Replace("tel:","")}
            ApplicationEndpoint {

                # Check if application endpoint is auto attendant or call queue
                $MatchingAA = Get-CsAutoAttendant | Where-Object {$_.ApplicationInstances -eq $aa.DefaultCallFlow.Menu.MenuOptions.CallTarget.Id}

                if ($MatchingAA) {

                    $defaultCallFlowTargetTypeFriendly = "[Auto Attendant"
                    $defaultCallFlowTargetName = "$($MatchingAA.Name)]"

                    if ($InvokedByNesting -eq $false) {
                        $aaDefaultCallFlowForwardsToAa = $true
                        $aaDefaultCallFlowNestedAaIdentity = $MatchingAA.Identity
                    }


                }

                else {

                    $MatchingCqAaDefaultCallFlow = Get-CsCallQueue | Where-Object {$_.ApplicationInstances -eq $aa.DefaultCallFlow.Menu.MenuOptions.CallTarget.Id}

                    $defaultCallFlowTargetTypeFriendly = "[Call Queue"
                    $defaultCallFlowTargetName = "$($MatchingCqAaDefaultCallFlow.Name)]"

                    if ($InvokedByNesting -eq $false) {
                        $aaDefaultCallFlowForwardsToCq = $true
                    }

                    else {
                        $aaNestedDefaultCallFlowForwardsToCq = $true
                    }

                }

            }
            SharedVoicemail {

                $defaultCallFlowTargetTypeFriendly = "Voicemail"
                $defaultCallFlowTargetName = (Get-MsolGroup -ObjectId $aa.DefaultCallFlow.Menu.MenuOptions.CallTarget.Id).DisplayName

            }
        }

        # Check if transfer target type is call queue
        if ($defaultCallFlowTargetTypeFriendly -eq "[Call Queue") {

            $MatchingCQIdentity = (Get-CsCallQueue | Where-Object {$_.ApplicationInstances -eq $aa.DefaultCallFlow.Menu.MenuOptions.CallTarget.Id}).Identity

            $mdAutoAttendantDefaultCallFlow = "defaultCallFlowGreeting$($aaDefaultCallFlowCounter)>$defaultCallFlowGreeting] --> defaultCallFlow$($aaDefaultCallFlowCounter)($defaultCallFlowAction) --> defaultCallFlowAction$($aaDefaultCallFlowCounter)($defaultCallFlowTargetTypeFriendly <br> $defaultCallFlowTargetName)"

            
        } # End if transfer target type is call queue

        # Check if default callflow action target is trasnfer call to target but something other than call queue
        else {

            $mdAutoAttendantDefaultCallFlow = "defaultCallFlowGreeting$($aaDefaultCallFlowCounter)>$defaultCallFlowGreeting] --> defaultCallFlow$($aaDefaultCallFlowCounter)($defaultCallFlowAction) --> defaultCallFlowAction$($aaDefaultCallFlowCounter)($defaultCallFlowTargetTypeFriendly <br> $defaultCallFlowTargetName)"

        }

    }

    # Check if default callflow action is disconnect call
    elseif ($defaultCallFlowAction -eq "DisconnectCall") {

        $mdAutoAttendantDefaultCallFlow = "defaultCallFlowGreeting$($aaDefaultCallFlowCounter)>$defaultCallFlowGreeting] --> defaultCallFlow$($aaDefaultCallFlowCounter)(($defaultCallFlowAction))"

    }
    
    
}

function Get-AutoAttendantAfterHoursCallFlow {
    param (
        [Parameter(Mandatory=$false)][String]$VoiceAppId,
        [Parameter(Mandatory=$false)][Bool]$InvokedByNesting = $false,
        [Parameter(Mandatory=$false)][String]$NestedAaCallFlowType
    )

    if (!$aaAfterHoursCallFlowCounter) {
        $aaAfterHoursCallFlowCounter = 0
    }

    $aaAfterHoursCallFlowCounter ++

    # Get after hours call flow
    $afterHoursCallFlow = ($aa.CallFlows | Where-Object {$_.Name -Match "after hours"})
    $afterHoursCallFlowAction = ($aa.CallFlows | Where-Object {$_.Name -Match "after hours"}).Menu.MenuOptions.Action.Value

    # Get after hours greeting
    $afterHoursCallFlowGreeting = "Greeting <br> $($afterHoursCallFlow.Greetings.ActiveType.Value)"

    # Check if after hours action is transfer call to target
    if ($afterHoursCallFlowAction -eq "TransferCallToTarget") {

        $afterHoursCallFlowTargetType = $afterHoursCallFlow.Menu.MenuOptions.CallTarget.Type.Value

        # Switch through after hours call flow target type
        switch ($afterHoursCallFlowTargetType) {
            User { 
                $afterHoursCallFlowTargetTypeFriendly = "User"
                $afterHoursCallFlowTargetName = (Get-MsolUser -ObjectId $($afterHoursCallFlow.Menu.MenuOptions.CallTarget.Id)).DisplayName}
            ExternalPstn { 
                $afterHoursCallFlowTargetTypeFriendly = "External PSTN"
                $afterHoursCallFlowTargetName = ($afterHoursCallFlow.Menu.MenuOptions.CallTarget.Id).Replace("tel:","")}
            ApplicationEndpoint {

                # Check if application endpoint is an auto attendant or a call queue
                $MatchingAA = Get-CsAutoAttendant | Where-Object {$_.ApplicationInstances -eq $afterHoursCallFlow.Menu.MenuOptions.CallTarget.Id}

                if ($MatchingAA) {

                    $afterHoursCallFlowTargetTypeFriendly = "[Auto Attendant"
                    $afterHoursCallFlowTargetName = "$($MatchingAA.Name)]"

                    if ($InvokedByNesting -eq $false) {
                        $aaAfterHoursCallFlowForwardsToAa = $true
                        $aaAfterHoursCallFlowNestedAaIdentity = $MatchingAA.Identity

                    }

                }

                else {

                    $MatchingCqAaAfterHoursCallFlow = Get-CsCallQueue | Where-Object {$_.ApplicationInstances -eq $afterHoursCallFlow.Menu.MenuOptions.CallTarget.Id}

                    $afterHoursCallFlowTargetTypeFriendly = "[Call Queue"
                    $afterHoursCallFlowTargetName = "$($MatchingCqAaAfterHoursCallFlow.Name)]"

                    if ($InvokedByNesting -eq $false) {
                        $aaAfterHoursCallFlowForwardsToCq = $true
                    }

                    else {
                        $aaNestedAfterHoursCallFlowForwardsToCq = $true
                    }

                }

            }
            SharedVoicemail {

                $afterHoursCallFlowTargetTypeFriendly = "Voicemail"
                $afterHoursCallFlowTargetName = (Get-MsolGroup -ObjectId $afterHoursCallFlow.Menu.MenuOptions.CallTarget.Id).DisplayName

            }
        }

        # Check if transfer target type is call queue
        if ($afterHoursCallFlowTargetTypeFriendly -eq "[Call Queue") {

            $MatchingCQIdentity = (Get-CsCallQueue | Where-Object {$_.ApplicationInstances -eq $aa.AfterHoursCallFlow.Menu.MenuOptions.CallTarget.Id}).Identity

            $mdAutoAttendantAfterHoursCallFlow = "afterHoursCallFlowGreeting$($aaAfterHoursCallFlowCounter)>$AfterHoursCallFlowGreeting] --> AfterHoursCallFlow$($aaAfterHoursCallFlowCounter)($AfterHoursCallFlowAction) --> AfterHoursCallFlowAction$($aaAfterHoursCallFlowCounter)($AfterHoursCallFlowTargetTypeFriendly <br> $AfterHoursCallFlowTargetName)"

            
        } # End if transfer target type is call queue

        # Check if AfterHours callflow action target is trasnfer call to target but something other than call queue
        else {

            $mdAutoAttendantAfterHoursCallFlow = "afterHoursCallFlowGreeting$($aaAfterHoursCallFlowCounter)>$AfterHoursCallFlowGreeting] --> AfterHoursCallFlow$($aaAfterHoursCallFlowCounter)($AfterHoursCallFlowAction) --> AfterHoursCallFlowAction$($aaAfterHoursCallFlowCounter)($AfterHoursCallFlowTargetTypeFriendly <br> $AfterHoursCallFlowTargetName)"

        }


        # Mermaid code for after hours call flow nodes
        $mdAutoAttendantAfterHoursCallFlow = "afterHoursCallFlowGreeting$($aaAfterHoursCallFlowCounter)>$AfterHoursCallFlowGreeting] --> afterHoursCallFlow$($aaAfterHoursCallFlowCounter)($afterHoursCallFlowAction) --> afterHoursCallFlowAction$($aaAfterHoursCallFlowCounter)($afterHoursCallFlowTargetTypeFriendly <br> $afterHoursCallFlowTargetName)"

    }

    elseif ($afterHoursCallFlowAction -eq "DisconnectCall") {

        $mdAutoAttendantAfterHoursCallFlow = "afterHoursCallFlowGreeting$($aaAfterHoursCallFlowCounter)>$AfterHoursCallFlowGreeting] --> afterHoursCallFlow$($aaAfterHoursCallFlowCounter)(($afterHoursCallFlowAction))"

    }
    

    

}

function Get-CallQueueCallFlow {
    param (
        [Parameter(Mandatory=$true)][String]$MatchingCQIdentity,
        [Parameter(Mandatory=$false)][Bool]$InvokedByNesting = $false,
        [Parameter(Mandatory=$false)][String]$NestedCQType

    )

    if (!$cqCallFlowCounter) {
        $cqCallFlowCounter = 0
    }

    $cqCallFlowCounter ++

    $MatchingCQ = Get-CsCallQueue -Identity $MatchingCQIdentity

    Write-Host "Function running for $($MatchingCQ.Name)" -ForegroundColor Magenta
    Write-Host "Function run number: $cqCallFlowCounter" -ForegroundColor Magenta
    Write-Host "Function running nested: $InvokedByNesting" -ForegroundColor Magenta

    # Store all neccessary call queue properties in variables
    $CqOverFlowThreshold = $MatchingCQ.OverflowThreshold
    $CqOverFlowAction = $MatchingCQ.OverflowAction.Value
    $CqTimeOut = $MatchingCQ.TimeoutThreshold
    $CqTimeoutAction = $MatchingCQ.TimeoutAction.Value
    $CqRoutingMethod = $MatchingCQ.RoutingMethod.Value
    $CqAgents = $MatchingCQ.Agents.ObjectId
    $CqAgentOptOut = $MatchingCQ.AllowOptOut
    $CqConferenceMode = $MatchingCQ.ConferenceMode
    $CqAgentAlertTime = $MatchingCQ.AgentAlertTime
    $CqPresenceBasedRouting = $MatchingCQ.PresenceBasedRouting
    $CqDistributionList = $MatchingCQ.DistributionLists
    $CqDefaultMusicOnHold = $MatchingCQ.UseDefaultMusicOnHold
    $CqWelcomeMusicFileName = $MatchingCQ.WelcomeMusicFileName

    # Check if call queue uses default music on hold
    if ($CqDefaultMusicOnHold -eq $true) {
        $CqMusicOnHold = "Default"
    }

    else {
        $CqMusicOnHold = "Custom"
    }

    # Check if call queue uses a greeting
    if (!$CqWelcomeMusicFileName) {
        $CqGreeting = "None"
    }

    else {
        $CqGreeting = "Audio File"

    }

    # Check if call queue useses users, group or teams channel as distribution list
    if (!$CqDistributionList) {

        $CqAgentListType = "Users"

    }

    else {

        if (!$MatchingCQ.ChannelId) {

            $CqAgentListType = "Group"

        }

        else {

            $CqAgentListType = "Teams Channel"

        }

    }

    if ($InvokedByNesting -eq $false) {

        if ($MatchingCQ.OverflowActionTarget.Id -eq $MatchingCQ.TimeoutActionTarget.Id) {
            $dynamicCqOverFlowActionTarget = "cqTimeoutActionTarget"
        }
    
        else {
            $dynamicCqOverFlowActionTarget = "cqOverFlowActionTarget"
        }  

    }

    else {

        if ($MatchingTimeoutCQ.Identity -eq $MatchingOverFlowCQ.Identity) {
            $dynamicCqOverFlowActionTarget = "cqTimeoutActionTarget"
        }
    
        else {
            $dynamicCqOverFlowActionTarget = "cqOverFlowActionTarget"
        } 

    }

    # Switch through call queue overflow action target
    switch ($CqOverFlowAction) {
        DisconnectWithBusy {
            $CqOverFlowActionFriendly = "cqOverFlowAction$($cqCallFlowCounter)((Disconnect Call))"
        }
        Forward {

            if ($MatchingCQ.OverflowActionTarget.Type -eq "User") {

                $MatchingOverFlowUser = (Get-MsolUser -ObjectId $MatchingCQ.OverflowActionTarget.Id).DisplayName

                $CqOverFlowActionFriendly = "cqOverFlowAction$($cqCallFlowCounter)(TransferCallToTarget) --> cqOverFlowActionTarget$($cqCallFlowCounter)(User <br> $MatchingOverFlowUser)"

            }

            elseif ($MatchingCQ.OverflowActionTarget.Type -eq "Phone") {

                $cqOverFlowPhoneNumber = ($MatchingCQ.OverflowActionTarget.Id).Replace("tel:","")

                $CqOverFlowActionFriendly = "cqOverFlowAction$($cqCallFlowCounter)(TransferCallToTarget) --> cqOverFlowActionTarget$($cqCallFlowCounter)(External Number <br> $cqOverFlowPhoneNumber)"
                
            }

            else {

                $MatchingOverFlowAA = (Get-CsAutoAttendant | Where-Object {$_.ApplicationInstances -eq $MatchingCQ.OverflowActionTarget.Id}).Name

                if ($MatchingOverFlowAA) {

                    $CqOverFlowActionFriendly = "cqOverFlowAction$($cqCallFlowCounter)(TransferCallToTarget) --> $dynamicCqOverFlowActionTarget$($cqCallFlowCounter)([Auto Attendant <br> $MatchingOverFlowAA])"

                }

                else {

                    $MatchingOverFlowCQ = (Get-CsCallQueue | Where-Object {$_.ApplicationInstances -eq $MatchingCQ.OverflowActionTarget.Id})

                    $CqOverFlowActionFriendly = "cqOverFlowAction$($cqCallFlowCounter)(TransferCallToTarget) --> $dynamicCqOverFlowActionTarget$($cqCallFlowCounter)([Call Queue <br> $($MatchingOverFlowCQ.Name)])"

                }

            }

        }
        SharedVoicemail {
            $MatchingOverFlowVoicemail = (Get-MsolGroup -ObjectId $MatchingCQ.OverflowActionTarget.Id).DisplayName

            if ($MatchingCQ.OverflowSharedVoicemailTextToSpeechPrompt) {

                $CqOverFlowVoicemailGreeting = "TextToSpeech"

            }

            else {

                $CqOverFlowVoicemailGreeting = "AudioFile"

            }

            $CqOverFlowActionFriendly = "cqOverFlowAction$($cqCallFlowCounter)(TransferCallToTarget) --> cqOverFlowVoicemailGreeting$($cqCallFlowCounter)>Greeting <br> $CqOverFlowVoicemailGreeting] --> cqOverFlowActionTarget$($cqCallFlowCounter)(Shared Voicemail <br> $MatchingOverFlowVoicemail)"

        }

    }

    # Switch through call queue timeout overflow action
    switch ($CqTimeoutAction) {
        Disconnect {
            $CqTimeoutActionFriendly = "cqTimeoutAction$($cqCallFlowCounter)((Disconnect Call))"
        }
        Forward {
    
            if ($MatchingCQ.TimeoutActionTarget.Type -eq "User") {

                $MatchingTimeoutUser = (Get-MsolUser -ObjectId $MatchingCQ.TimeoutActionTarget.Id).DisplayName
    
                $CqTimeoutActionFriendly = "cqTimeoutAction$($cqCallFlowCounter)(TransferCallToTarget) --> cqTimeoutActionTarget$($cqCallFlowCounter)(User <br> $MatchingTimeoutUser)"
    
            }
    
            elseif ($MatchingCQ.TimeoutActionTarget.Type -eq "Phone") {
    
                $cqTimeoutPhoneNumber = ($MatchingCQ.TimeoutActionTarget.Id).Replace("tel:","")
    
                $CqTimeoutActionFriendly = "cqTimeoutAction$($cqCallFlowCounter)(TransferCallToTarget) --> cqTimeoutActionTarget$($cqCallFlowCounter)(External Number <br> $cqTimeoutPhoneNumber)"
                
            }
    
            else {
    
                $MatchingTimeoutAA = (Get-CsAutoAttendant | Where-Object {$_.ApplicationInstances -eq $MatchingCQ.TimeoutActionTarget.Id}).Name
    
                if ($MatchingTimeoutAA) {
    
                    $CqTimeoutActionFriendly = "cqTimeoutAction$($cqCallFlowCounter)(TransferCallToTarget) --> cqTimeoutActionTarget$($cqCallFlowCounter)([Auto Attendant <br> $MatchingTimeoutAA])"
    
                }
    
                else {
    
                    $MatchingTimeoutCQ = (Get-CsCallQueue | Where-Object {$_.ApplicationInstances -eq $MatchingCQ.TimeoutActionTarget.Id})

                    $CqTimeoutActionFriendly = "cqTimeoutAction$($cqCallFlowCounter)(TransferCallToTarget) --> cqTimeoutActionTarget$($cqCallFlowCounter)([Call Queue <br> $($MatchingTimeoutCQ.Name)])"
    
                }
    
            }
    
        }
        SharedVoicemail {
            $MatchingTimeoutVoicemail = (Get-MsolGroup -ObjectId $MatchingCQ.TimeoutActionTarget.Id).DisplayName
    
            if ($MatchingCQ.TimeoutSharedVoicemailTextToSpeechPrompt) {
    
                $CqTimeoutVoicemailGreeting = "TextToSpeech"
    
            }
    
            else {
    
                $CqTimeoutVoicemailGreeting = "AudioFile"
    
            }
    
            $CqTimeoutActionFriendly = "cqTimeoutAction$($cqCallFlowCounter)(TransferCallToTarget) --> cqTimeoutVoicemailGreeting$($cqCallFlowCounter)>Greeting <br> $CqTimeoutVoicemailGreeting] --> cqTimeoutActionTarget$($cqCallFlowCounter)(Shared Voicemail <br> $MatchingTimeoutVoicemail)"
    
        }
    
    }

    # Create empty mermaid element for agent list
    $mdCqAgentsDisplayNames = @"
"@

    # Define agent counter for unique mermaid element names
    $AgentCounter = 1

    # add each agent to the empty agents mermaid element
    foreach ($CqAgent in $CqAgents) {
        $AgentDisplayName = (Get-MsolUser -ObjectId $CqAgent).DisplayName

        $AgentDisplayNames = "agentListType$($cqCallFlowCounter) --> agent$($cqCallFlowCounter)$($AgentCounter)($AgentDisplayName) --> timeOut$($cqCallFlowCounter)`n"

        $mdCqAgentsDisplayNames += $AgentDisplayNames

        $AgentCounter ++
    }

    switch ($voiceAppType) {
        "Auto Attendant" {

            if ($NestedCQType -eq "TimeOut") {

                if ($MatchingCqAaDefaultCallFlow -and $MatchingCqAaAfterHoursCallFlow) {
                    $voiceAppTypeSpecificCallFlow = "cqTimeoutActionTarget$($cqCallFlowCounter -2) --> cqGreeting$($cqCallFlowCounter)>Greeting <br> $CqGreeting]"
                }

                else {
                    $voiceAppTypeSpecificCallFlow = "cqTimeoutActionTarget$($cqCallFlowCounter -1) --> cqGreeting$($cqCallFlowCounter)>Greeting <br> $CqGreeting]"
                }
                
            }

            elseif ($NestedCQType -eq "OverFlow") {
                $voiceAppTypeSpecificCallFlow = "cqOverFlowActionTarget$($cqCallFlowCounter -2) --> cqGreeting$($cqCallFlowCounter)>Greeting <br> $CqGreeting]"
            }

            elseif ($NestedCQType -eq "AaDefaultCallFlow") {
                $voiceAppTypeSpecificCallFlow = "defaultCallFlowAction$($aaDefaultCallFlowCounter)($defaultCallFlowTargetTypeFriendly <br> $defaultCallFlowTargetName) --> cqGreeting$($cqCallFlowCounter)>Greeting <br> $CqGreeting]"
            }

            elseif ($NestedCQType -eq "AaAfterHoursCallFlow") {
                $voiceAppTypeSpecificCallFlow = "afterHoursCallFlowAction$($aaAfterHoursCallFlowCounter) --> cqGreeting$($cqCallFlowCounter)>Greeting <br> None]"
            }

            else {
                $voiceAppTypeSpecificCallFlow = "defaultCallFlowAction$($aaDefaultCallFlowCounter)($defaultCallFlowTargetTypeFriendly <br> $defaultCallFlowTargetName) --> cqGreeting$($cqCallFlowCounter)>Greeting <br> $CqGreeting]"
            }

        }
        "Call Queue" {

            if ($NestedCQType -eq "TimeOut") {
                $voiceAppTypeSpecificCallFlow = "--> cqGreeting$($cqCallFlowCounter)>Greeting <br> $CqGreeting]"
            }

            elseif ($NestedCQType -eq "OverFlow") {
                $voiceAppTypeSpecificCallFlow = "cqOverFlowActionTarget$($cqCallFlowCounter -2) --> cqGreeting$($cqCallFlowCounter)>Greeting <br> $CqGreeting]"
            }

            else {
                $voiceAppTypeSpecificCallFlow = $null
            }

        }

    }

    if ($cqCallFlowCounter -le 1 -and $ShowNestedPhoneNumbers -eq $true) {

        $nestedCallQueues = @()
    
        $nestedCallQueues += $MatchingCQ
        $nestedCallQueues += $MatchingTimeoutCQ
        $nestedCallQueues += $MatchingOverFlowCQ
        $nestedCallQueues += $MatchingCqAaAfterHoursCallFlow
    
        $nestedCallQueueTopLevelNumbers = @()
        $nestedCallQueueTopLevelNumbersCheck = @()
    
        if (!$nestedTopLevelCqCounter) {
            $nestedTopLevelCqCounter = 0
        }
    
        $nestedTopLevelCqCounter ++
    
        foreach ($nestedCallQueue in $nestedCallQueues) {
            
            $cqAssociatedApplicationInstances = $nestedCallQueue.DisplayApplicationInstances.Split("`n")
    
    
            foreach ($cqAssociatedApplicationInstance in $cqAssociatedApplicationInstances) {
    
                $nestedCallQueueTopLevelNumber = ((Get-CsOnlineApplicationInstance -Identity $cqAssociatedApplicationInstance).PhoneNumber).Replace("tel:","")
    
                if ($nestedCallQueueTopLevelNumber) {
    
                    if ($MatchingCQ.DisplayApplicationInstances -match $cqAssociatedApplicationInstance -and $voiceAppType -eq "Auto Attendant" -and $defaultCallFlowTargetTypeFriendly -eq "[Call Queue") {
    
                        $nestedCallQueueTopLevelNumberTargetNode = "((Incoming Call at <br> $($nestedCallQueueTopLevelNumber))) -...-> defaultCallFlowAction$($aaDefaultCallFlowCounter)`n"
                        $nestedCallQueueTopLevelNumberNode = "additionalStart$($nestedTopLevelCqCounter)" + $nestedCallQueueTopLevelNumberTargetNode
                        
                        if ($nestedCallQueueTopLevelNumbersCheck -notcontains $nestedCallQueueTopLevelNumberTargetNode) {
    
                            $nestedCallQueueTopLevelNumbersCheck += $nestedCallQueueTopLevelNumberTargetNode
    
                            $nestedCallQueueTopLevelNumbers += $nestedCallQueueTopLevelNumberNode
    
                            $nestedTopLevelCqCounter ++
    
                        }
    
                    }
    
                    if ($MatchingTimeoutCQ.DisplayApplicationInstances -match $cqAssociatedApplicationInstance) {
                        
                        $nestedCallQueueTopLevelNumberTargetNode = "((Incoming Call at <br> $($nestedCallQueueTopLevelNumber))) -...-> cqTimeoutActionTarget$($cqCallFlowCounter)`n"
                        $nestedCallQueueTopLevelNumberNode = "additionalStart$($nestedTopLevelCqCounter)" +$nestedCallQueueTopLevelNumberTargetNode
                        
                        if ($nestedCallQueueTopLevelNumbersCheck -notcontains $nestedCallQueueTopLevelNumberTargetNode) {
    
                            $nestedCallQueueTopLevelNumbersCheck += $nestedCallQueueTopLevelNumberTargetNode
    
                            $nestedCallQueueTopLevelNumbers += $nestedCallQueueTopLevelNumberNode
    
                            $nestedTopLevelCqCounter ++
    
                        }
    
                    }
    
                    if ($MatchingOverFlowCQ.DisplayApplicationInstances -match $cqAssociatedApplicationInstance) {
                        
                        $nestedCallQueueTopLevelNumberTargetNode = "((Incoming Call at <br> $($nestedCallQueueTopLevelNumber))) -...-> $dynamicCqOverFlowActionTarget$($cqCallFlowCounter)`n"
                        $nestedCallQueueTopLevelNumberNode = "additionalStart$($nestedTopLevelCqCounter)" +$nestedCallQueueTopLevelNumberTargetNode
                        
                        if ($nestedCallQueueTopLevelNumbersCheck -notcontains $nestedCallQueueTopLevelNumberTargetNode) {
    
                            $nestedCallQueueTopLevelNumbersCheck += $nestedCallQueueTopLevelNumberTargetNode
    
                            $nestedCallQueueTopLevelNumbers += $nestedCallQueueTopLevelNumberNode
    
                            $nestedTopLevelCqCounter ++
    
                        }
    
                    }

                    if ($MatchingCqAaAfterHoursCallFlow.DisplayApplicationInstances -match $cqAssociatedApplicationInstance) {
                        
                        $nestedCallQueueTopLevelNumberTargetNode = "((Incoming Call at <br> $($nestedCallQueueTopLevelNumber))) -...-> afterHoursCallFlowAction$($aaAfterHoursCallFlowCounter)`n"
                        $nestedCallQueueTopLevelNumberNode = "additionalStart$($nestedTopLevelCqCounter)" +$nestedCallQueueTopLevelNumberTargetNode
                        
                        if ($nestedCallQueueTopLevelNumbersCheck -notcontains $nestedCallQueueTopLevelNumberTargetNode) {
    
                            $nestedCallQueueTopLevelNumbersCheck += $nestedCallQueueTopLevelNumberTargetNode
    
                            $nestedCallQueueTopLevelNumbers += $nestedCallQueueTopLevelNumberNode
    
                            $nestedTopLevelCqCounter ++
    
                        }
    
                    }
    
    
    
                }
    
                else {
                    $nestedCallQueueTopLevelNumbers = $null
                }
    
            }
    
        }
    
    }

    else {
        $nestedCallQueueTopLevelNumbers = $null
    }

    # Create default callflow mermaid code

$mdCallQueueCallFlow =@"
$voiceAppTypeSpecificCallFlow
--> overFlow$($cqCallFlowCounter){More than $CqOverFlowThreshold <br> Active Calls}
overFlow$($cqCallFlowCounter) ---> |Yes| $CqOverFlowActionFriendly
overFlow$($cqCallFlowCounter) ---> |No| routingMethod$($cqCallFlowCounter)

$nestedCallQueueTopLevelNumbers

subgraph Call Distribution
subgraph CQ Settings
routingMethod$($cqCallFlowCounter)[(Routing Method: $CqRoutingMethod)] --> agentAlertTime$($cqCallFlowCounter)
agentAlertTime$($cqCallFlowCounter)[(Agent Alert Time: $CqAgentAlertTime)] -.- cqMusicOnHold$($cqCallFlowCounter)
cqMusicOnHold$($cqCallFlowCounter)[(Music On Hold: $CqMusicOnHold)] -.- conferenceMode$($cqCallFlowCounter)
conferenceMode$($cqCallFlowCounter)[(Conference Mode Enabled: $CqConferenceMode)] -.- agentOptOut$($cqCallFlowCounter)
agentOptOut$($cqCallFlowCounter)[(Agent Opt Out Allowed: $CqAgentOptOut)] -.- presenceBasedRouting$($cqCallFlowCounter)
presenceBasedRouting$($cqCallFlowCounter)[(Presence Based Routing: $CqPresenceBasedRouting)] -.- timeOut$($cqCallFlowCounter)
timeOut$($cqCallFlowCounter)[(Timeout: $CqTimeOut Seconds)]
end
subgraph Agents $($MatchingCQ.Name)
agentAlertTime$($cqCallFlowCounter) --> agentListType$($cqCallFlowCounter)[(Agent List Type: $CqAgentListType)]
$mdCqAgentsDisplayNames
end
end

timeOut$($cqCallFlowCounter) --> cqResult$($cqCallFlowCounter){Call Connected?}
cqResult$($cqCallFlowCounter) --> |Yes| cqEnd$($cqCallFlowCounter)((Call Connected))
cqResult$($cqCallFlowCounter) --> |No| $CqTimeoutActionFriendly

"@

    if ($InvokedByNesting -eq $false) {

        if ($mdInitialCallQueueCallFlow) {
            $mdInitialCallQueueCallFlow += $mdCallQueueCallFlow
        }

        else {
            $mdInitialCallQueueCallFlow = $mdCallQueueCallFlow
        }
    }

    
}