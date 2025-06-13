# Connect to Azure account
Connect-AzAccount

# Retrieve all subscriptions
$Subscriptions = Get-AzSubscription

# Create a List object to store results
$Results = [System.Collections.Generic.List[PSObject]]::new()

# Function to resolve group members
function Resolve-GroupMembers {
    param (
        [string]$GroupId,
        [string]$GroupName,
        [string]$AssignmentScope,
        [string]$RoleName,
        [string]$SubscriptionName,
        [string]$SubscriptionId
    )

    # Get all members of the group
    $GroupMembers = Get-AzADGroupMember -GroupObjectId $GroupId -ErrorAction SilentlyContinue

    if (-not $GroupMembers) {
        Write-Warning "Group $GroupName has no members or member retrieval failed."
        return
    }

    Write-Output "Processing members in group: $GroupName"

    foreach ($Member in $GroupMembers) {
        # If 'Type' is explicitly 'User', process as a user
        if ($Member.Type -eq "User") {
            $User = Get-AzADUser -ObjectId $Member.Id -ErrorAction SilentlyContinue
            if ($User) {
                $Results.Add([PSCustomObject]@{
                    SubscriptionName   = $SubscriptionName
                    SubscriptionId     = $SubscriptionId
                    PrincipalName      = $User.UserPrincipalName
                    DisplayName        = $User.DisplayName
                    PrincipalType      = "User (via Group)"
                    AssignmentScope    = $AssignmentScope
                    RoleName           = $RoleName
                    GroupName          = $GroupName
                })
            }
        }
        # Fallback: If 'Type' is blank, attempt to resolve as a user
        elseif ([string]::IsNullOrEmpty($Member.Type)) {
            Write-Warning "Member $($Member.Id) in group $GroupName has a blank 'Type'. Attempting to resolve as a User."
            $User = Get-AzADUser -ObjectId $Member.Id -ErrorAction SilentlyContinue
            if ($User) {
                $Results.Add([PSCustomObject]@{
                    SubscriptionName   = $SubscriptionName
                    SubscriptionId     = $SubscriptionId
                    PrincipalName      = $User.UserPrincipalName
                    DisplayName        = $User.DisplayName
                    PrincipalType      = "User (via Group) (Blank Type)"
                    AssignmentScope    = $AssignmentScope
                    RoleName           = $RoleName
                    GroupName          = $GroupName
                })
            }
        }
    }
}

# Process each subscription
foreach ($Subscription in $Subscriptions) {
    try {
        Set-AzContext -SubscriptionId $Subscription.Id
        Write-Output "Processing subscription: $($Subscription.Name)"

        # Get all "Owner" role assignments
        $RoleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$($Subscription.Id)" | Where-Object { $_.RoleDefinitionName -eq "Owner" }

        if (-not $RoleAssignments) {
            Write-Warning "No 'Owner' role assignments found for subscription $($Subscription.Name)."
            continue
        }

        foreach ($Assignment in $RoleAssignments) {
            $PrincipalType = $Assignment.ObjectType

            # Handle direct user assignments
            if ($PrincipalType -eq "User") {
                $User = Get-AzADUser -ObjectId $Assignment.ObjectId -ErrorAction SilentlyContinue
                if ($User) {
                    $Results.Add([PSCustomObject]@{
                        SubscriptionName   = $Subscription.Name
                        SubscriptionId     = $Subscription.Id
                        PrincipalName      = $User.UserPrincipalName
                        DisplayName        = $User.DisplayName
                        PrincipalType      = "User"
                        AssignmentScope    = $Assignment.Scope
                        RoleName           = $Assignment.RoleDefinitionName
                        GroupName          = ""
                    })
                }
            }
            # Handle group assignments
            elseif ($PrincipalType -eq "Group") {
                $Group = Get-AzADGroup -ObjectId $Assignment.ObjectId -ErrorAction SilentlyContinue
                if ($Group) {
                    Write-Output "Processing group: $($Group.DisplayName)"
                    Resolve-GroupMembers -GroupId $Group.Id -GroupName $Group.DisplayName -AssignmentScope $Assignment.Scope -RoleName $Assignment.RoleDefinitionName -SubscriptionName $Subscription.Name -SubscriptionId $Subscription.Id
                } else {
                    Write-Warning "Unable to resolve group $($Assignment.ObjectId) in subscription $($Subscription.Name)."
                }
            }
        }
    } catch {
        Write-Error "Error processing subscription $($Subscription.Name): $_"
        continue
    }
}

# Export results to CSV
$ExportPath = "OwnerRoleAssignments_AllSubscriptions.csv"
$Results | Export-Csv -Path $ExportPath -NoTypeInformation -Force

Write-Output "Script execution completed. Results exported to '$ExportPath'."