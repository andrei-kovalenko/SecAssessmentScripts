# Login into your Azure account (if not already logged in)
Write-Host "Checking Azure login status..."
$accountInfo = az account show --query "name" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Azure login required. Logging in..."
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Azure login failed."
        exit 1
    }
}

# Function to get route table and associated subnets
function Get-RouteTableDetails {
    Write-Host "Starting execution of Get-RouteTableDetails..."

    # Initialize an empty array to store data
    $routeTableData = @()

    # Get all subscriptions
    Write-Host "Retrieving subscriptions..."
    $subscriptions = az account list --query "[].{Name:name, Id:id}" -o json | ConvertFrom-Json

    foreach ($subscription in $subscriptions) {
        $subscriptionName = $subscription.Name
        $subscriptionId = $subscription.Id
        Write-Host "Processing subscription: $subscriptionName ($subscriptionId)"

        # Set subscription context
        az account set --subscription $subscriptionId

        # Get all resource groups in the subscription
        Write-Host "  Retrieving resource groups for subscription $subscriptionName..."
        $resourceGroups = az group list --query "[].name" -o json | ConvertFrom-Json

        foreach ($rg_name in $resourceGroups) {
            Write-Host "    Processing resource group: $rg_name"

            # Get all route tables in the resource group
            $routeTables = az network route-table list --resource-group "$rg_name" --query "[].{Name:name, Id:id}" -o json | ConvertFrom-Json

            foreach ($routeTable in $routeTables) {
                $routeTableName = $routeTable.Name
                $routeTableId = $routeTable.Id
                Write-Host "      Processing route table: $routeTableName"

                # Get routes in the route table for diagnostics
                $routes = az network route-table route list --resource-group "$rg_name" --route-table-name "$routeTableName" -o json | ConvertFrom-Json

                foreach ($route in $routes) {
                    $addressPrefix = $route.addressPrefix
                    $nextHopType = $route.nextHopType
                    $nextHopIpAddress = $route.nextHopIpAddress

                    # Get VNets in the resource group
                    Write-Host "        Determining subnets associated with route table $routeTableName..."

                    # Get all subnets and specifically filter those pointing to this route table
                    $vnets = az network vnet list --resource-group "$rg_name" -o json | ConvertFrom-Json

                    foreach ($vnet in $vnets) {
                        $vnetName = $vnet.Name

                        # List subnets explicitly associated with the route table
                        $subnets = az network vnet subnet list --resource-group "$rg_name" --vnet-name "$vnetName" --query "[?routeTable.id == '$routeTableId']" -o json | ConvertFrom-Json

                        foreach ($subnet in $subnets) {
                            $subnetName = $subnet.name
                            $subnetAddressRange = $subnet.addressPrefix

                            # Get associated NSG info (if any)
                            $nsgId = $subnet.networkSecurityGroup.id
                            $nsgName = $(if ($nsgId) { $nsgId.Split("/")[-1] } else { "None" })

                            # Log progress for each subnet
                            Write-Host "          Found subnet: $subnetName in VNet: $vnetName, AddressRange: $subnetAddressRange, NSG: $nsgName"

                            # Add details to routeTableData
                            $routeTableData += [pscustomobject]@{
                                SubscriptionName   = $subscriptionName
                                ResourceGroupName  = $rg_name
                                RouteTableName     = $routeTableName
                                AddressPrefix      = $addressPrefix
                                NextHopType        = $nextHopType
                                NextHopIPAddress   = $nextHopIpAddress
                                VNetName           = $vnetName
                                SubnetName         = $subnetName
                                SubnetAddressRange = $subnetAddressRange
                                NSG                = $nsgName
                            }
                        }
                    }
                }
            }
        }
    }

    # Export results to CSV
    $outputFile = "RouteTableDetails.csv"
    Write-Host "Exporting data to CSV: $outputFile..."
    $routeTableData | Export-Csv -Path $outputFile -NoTypeInformation

    Write-Host "Execution complete. Results saved to $outputFile."
}

# Execute the function
Get-RouteTableDetails