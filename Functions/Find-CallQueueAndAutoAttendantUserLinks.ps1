<#
    .SYNOPSIS
    Runs M365CallFlowVisualizer.ps1 for all, only Auto Attendants or only Call Queues in order to check which Voice Apps a user is part of and exports a CSV file. This will not generate any diagrams.
    
    .DESCRIPTION
    Author:             Martin Heusser
    Version:            1.0.0
    Changelog:          .\Changelog.md

#>

function Find-CallQueueAndAutoAttendantUserLinks {
    param (
        [Parameter(Mandatory=$false)][String]$SearchUserId,
        [Parameter(Mandatory=$false)][ValidateSet("All","CallQueues","AutoAttendants")][String]$SearchScope = "All"
    )

    . .\Functions\Connect-M365CFV.ps1

    . Connect-M365CFV

    if (!$SearchUserId) {

        $SearchUserId = (Get-MgUser -Top 10000 | Select-Object DisplayName, UserPrincipalName, Id | Out-GridView -Title "Select a User..." -PassThru).Id

    }

    $userLinkVoiceApps = @()

    $searchScopeIncludedVoiceApps = @()

    #$searchScopeIncludedVoiceApps += "09900154-b7e6-410c-bc9b-57346aea15f1"

    switch ($SearchScope) {
        All {
            $searchScopeIncludedVoiceApps += (Get-CsCallQueue -WarningAction SilentlyContinue).Identity
            $searchScopeIncludedVoiceApps += (Get-CsAutoAttendant).Identity
        }
        CallQueues {
            $searchScopeIncludedVoiceApps += (Get-CsCallQueue -WarningAction SilentlyContinue).Identity
        }
        AutoAttendants {
            $searchScopeIncludedVoiceApps += (Get-CsAutoAttendant).Identity
        }
        Default {}
    }

    $searchScopeIncludedVoiceApps = "28c273bc-eeb1-4e51-b284-2b157e26608a"

    foreach ($searchScopeIncludedVoiceApp in $searchScopeIncludedVoiceApps) {

        . .\M365CallFlowVisualizerV2.ps1 -Identity $searchScopeIncludedVoiceApp -FindUserLinks -SaveToFile $false -SetClipBoard $false -ExportHtml $false -ShowNestedCallFlows $false -ShowUserCallingSettings $false

    }

    $userLinkVoiceApps = $userLinkVoiceApps | Where-Object {$_.UserId -eq $SearchUserId} | Sort-Object VoiceAppName, VoiceAppActionType -Unique

    return $userLinkVoiceApps, $userLinkVoiceApps | Export-CSV -Path ".\Output\VoiceAppsLinkedTo_$($SearchUserId).csv" -Delimiter ";" -NoTypeInformation -Encoding UTF8 -Force

}