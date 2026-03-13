# Read input file
$items = Get-Content "C:\git\alz-graph-queries\items_no_query.json" | ConvertFrom-Json

# Process each item
$output = @()

foreach ($item in $items) {
    $entry = [ordered]@{
        guid = $item.guid
        category = $item.category
        subcategory = $item.subcategory
        severity = $item.severity
        text = $item.text
        queryable = $false
        reason = ""
        query = ""
        description = ""
    }
    
    $text = $item.text.ToLower()
    $category = $item.category.ToLower()
    $subcategory = $item.subcategory.ToLower()
    
    # Determine if queryable based on content
    switch -Regex ($text) {
        # Non-queryable patterns - Process/Organizational/Entra/Billing/DevOps
        'document|define|establish|process|procedure|review|approval|governance framework|runbook|playbook|strategy' {
            if ($text -notmatch 'nsg|firewall|route|policy|lock|tag|diagnostic|log|alert|backup|encryption|disk|network|subnet|vnet|expressroute|vpn|storage|key vault|rbac|role|security center|defender') {
                $entry.queryable = $false
                $entry.reason = "Organizational process or documentation requirement - not directly queryable via ARG"
                break
            }
        }
        'train|skill|knowledge|awareness|education|competency' {
            $entry.queryable = $false
            $entry.reason = "Training/knowledge requirement - not directly queryable via ARG"
            break
        }
        'entra|azure ad|microsoft entra|tenant|b2b|b2c|authentication method|conditional access policy|pim|privileged identity' {
            if ($text -notmatch 'managed identity|service principal|rbac|role assignment') {
                $entry.queryable = $false
                $entry.reason = "Entra ID/tenant management - not available in ARG tables"
                break
            }
        }
        'billing|invoice|cost management account|enterprise agreement|csp partner|support request|subscription transfer|reservation' {
            if ($text -notmatch 'budget|tag|resource group') {
                $entry.queryable = $false
                $entry.reason = "Billing/commercial relationship - not available in ARG tables"
                break
            }
        }
        'devops|cicd|ci/cd|pipeline|deployment automation|iac|infrastructure as code|repository|git|version control|pull request' {
            if ($text -notmatch 'resource|deployment|policy|lock|tag') {
                $entry.queryable = $false
                $entry.reason = "DevOps practice - not directly queryable via ARG"
                break
            }
        }
        'service health|support ticket|sla|microsoft support|azure support' {
            $entry.queryable = $false
            $entry.reason = "Service health/support - not available in ARG tables"
            break
        }
        'disaster recovery plan|business continuity plan|rto|rpo' {
            if ($text -notmatch 'backup|replication|availability zone|region|geo-redundant') {
                $entry.queryable = $false
                $entry.reason = "DR planning process - not directly queryable via ARG"
                break
            }
        }
    }
    
    # If still false, check if we can make it queryable
    if (-not $entry.queryable) {
        switch -Regex ($text) {
            # Network resources
            'virtual network peering|vnet peering' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/virtualnetworks' | mvexpand peerings = properties.virtualNetworkPeerings | where peerings.properties.peeringState != 'Connected' | project id, name, location, peeringName = peerings.name, peeringState = peerings.properties.peeringState"
                $entry.description = "Find VNet peerings not in Connected state"
                break
            }
            'ddos protection|ddos standard' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/virtualnetworks' | where properties.enableDdosProtection != true | project id, name, location, enableDdosProtection = properties.enableDdosProtection"
                $entry.description = "Find VNets without DDoS Protection enabled"
                break
            }
            'network security group|nsg' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/networksecuritygroups' | project id, name, location, resourceGroup, securityRules = properties.securityRules"
                $entry.description = "List all NSGs and their security rules"
                break
            }
            'azure firewall' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/azurefirewalls' | project id, name, location, sku = properties.sku.tier, threatIntelMode = properties.threatIntelMode"
                $entry.description = "List all Azure Firewalls with SKU and threat intel mode"
                break
            }
            'route table|user-defined route|udr' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/routetables' | project id, name, location, routes = properties.routes, disableBgpRoutePropagation = properties.disableBgpRoutePropagation"
                $entry.description = "List all route tables with their routes"
                break
            }
            'expressroute|express route' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/expressroutecircuits' | project id, name, location, provisioningState = properties.provisioningState, circuitProvisioningState = properties.circuitProvisioningState, serviceProviderProvisioningState = properties.serviceProviderProvisioningState"
                $entry.description = "List ExpressRoute circuits with provisioning states"
                break
            }
            'vpn gateway|virtual network gateway' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/virtualnetworkgateways' | project id, name, location, gatewayType = properties.gatewayType, vpnType = properties.vpnType, sku = properties.sku.name"
                $entry.description = "List all VPN/ER gateways with SKU information"
                break
            }
            'private endpoint' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/privateendpoints' | project id, name, location, privateLinkServiceConnections = properties.privateLinkServiceConnections, subnet = properties.subnet.id"
                $entry.description = "List all private endpoints and their connections"
                break
            }
            'dns|name resolution' {
                if ($text -match 'private dns') {
                    $entry.queryable = $true
                    $entry.query = "resources | where type =~ 'microsoft.network/privatednszones' | project id, name, location, numberOfRecordSets = properties.numberOfRecordSets, virtualNetworkLinks = properties.virtualNetworkLinks"
                    $entry.description = "List private DNS zones"
                }
                break
            }
            'subnet' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/virtualnetworks' | mvexpand subnets = properties.subnets | project vnetId = id, vnetName = name, subnetName = subnets.name, addressPrefix = subnets.properties.addressPrefix, nsg = subnets.properties.networkSecurityGroup.id"
                $entry.description = "List all subnets with their address prefixes and NSG assignments"
                break
            }
            'load balancer' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/loadbalancers' | project id, name, location, sku = sku.name, frontendIPConfigurations = properties.frontendIPConfigurations"
                $entry.description = "List all load balancers with SKU"
                break
            }
            'application gateway' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/applicationgateways' | project id, name, location, sku = properties.sku.tier, wafEnabled = properties.webApplicationFirewallConfiguration.enabled"
                $entry.description = "List application gateways with WAF status"
                break
            }
            'public ip' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.network/publicipaddresses' | project id, name, location, ipAddress = properties.ipAddress, allocationMethod = properties.publicIPAllocationMethod, sku = sku.name"
                $entry.description = "List all public IP addresses"
                break
            }
            
            # Storage
            'storage account' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.storage/storageaccounts' | project id, name, location, sku = sku.name, kind, httpsOnly = properties.supportsHttpsTrafficOnly, minimumTlsVersion = properties.minimumTlsVersion"
                $entry.description = "List storage accounts with security settings"
                break
            }
            
            # Security
            'microsoft defender|azure security center|defender for cloud' {
                $entry.queryable = $true
                $entry.query = "securityresources | where type =~ 'microsoft.security/pricings' | project id, name, pricingTier = properties.pricingTier"
                $entry.description = "List Defender for Cloud pricing tiers by plan"
                break
            }
            'security alert|security incident' {
                $entry.queryable = $true
                $entry.query = "securityresources | where type =~ 'microsoft.security/alerts' | where properties.status == 'Active' | project id, alertDisplayName = properties.alertDisplayName, severity = properties.severity, compromisedEntity = properties.compromisedEntity"
                $entry.description = "List active security alerts from Defender for Cloud"
                break
            }
            'vulnerability|security assessment' {
                $entry.queryable = $true
                $entry.query = "securityresources | where type =~ 'microsoft.security/assessments' | where properties.status.code == 'Unhealthy' | project id, displayName = properties.displayName, resourceId = properties.resourceDetails.id, status = properties.status.code"
                $entry.description = "List unhealthy security assessments"
                break
            }
            'encryption|encrypt' {
                if ($text -match 'disk') {
                    $entry.queryable = $true
                    $entry.query = "resources | where type =~ 'microsoft.compute/disks' | where properties.encryption.type != 'EncryptionAtRestWithPlatformAndCustomerKeys' and properties.encryption.type != 'EncryptionAtRestWithCustomerKey' | project id, name, location, encryptionType = properties.encryption.type"
                    $entry.description = "Find disks not using customer-managed keys"
                } elseif ($text -match 'storage') {
                    $entry.queryable = $true
                    $entry.query = "resources | where type =~ 'microsoft.storage/storageaccounts' | where properties.encryption.requireInfrastructureEncryption != true | project id, name, location, infrastructureEncryption = properties.encryption.requireInfrastructureEncryption"
                    $entry.description = "Find storage accounts without infrastructure encryption"
                }
                break
            }
            'key vault' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.keyvault/vaults' | project id, name, location, enableSoftDelete = properties.enableSoftDelete, enablePurgeProtection = properties.enablePurgeProtection, sku = properties.sku.name"
                $entry.description = "List Key Vaults with soft delete and purge protection status"
                break
            }
            'managed identity|managed identities' {
                $entry.queryable = $true
                $entry.query = "resources | where identity has 'principalId' | project id, name, type, location, identityType = identity.type, principalId = identity.principalId"
                $entry.description = "List resources with managed identities"
                break
            }
            'rbac|role assignment' {
                $entry.queryable = $true
                $entry.query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | project id, principalId = properties.principalId, roleDefinitionId = properties.roleDefinitionId, scope = properties.scope"
                $entry.description = "List all role assignments"
                break
            }
            
            # Policy
            'azure policy|policy assignment' {
                $entry.queryable = $true
                $entry.query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | project id, name, displayName = properties.displayName, enforcementMode = properties.enforcementMode, policyDefinitionId = properties.policyDefinitionId"
                $entry.description = "List policy assignments with enforcement mode"
                break
            }
            'non-compliant|compliance|policy compliance' {
                $entry.queryable = $true
                $entry.query = "policyresources | where type =~ 'microsoft.policyinsights/policystates' | where properties.complianceState == 'NonCompliant' | project policyAssignmentId = properties.policyAssignmentId, policyDefinitionId = properties.policyDefinitionId, resourceId = properties.resourceId, complianceState = properties.complianceState"
                $entry.description = "Find non-compliant resources"
                break
            }
            
            # Management
            'resource lock' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.authorization/locks' | project id, name, lockLevel = properties.level, notes = properties.notes, resourceId = split(id, '/providers/Microsoft.Authorization/locks/')[0]"
                $entry.description = "List all resource locks"
                break
            }
            'diagnostic|diagnostic setting' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.insights/diagnosticsettings' | project id, name, resourceId = split(id, '/providers/microsoft.insights/diagnosticSettings/')[0], logs = properties.logs, metrics = properties.metrics"
                $entry.description = "List diagnostic settings for resources"
                break
            }
            'log analytics|log analytics workspace' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.operationalinsights/workspaces' | project id, name, location, sku = properties.sku.name, retentionInDays = properties.retentionInDays"
                $entry.description = "List Log Analytics workspaces with retention"
                break
            }
            'alert|action group' {
                if ($text -match 'action group') {
                    $entry.queryable = $true
                    $entry.query = "resources | where type =~ 'microsoft.insights/actiongroups' | project id, name, location, enabled = properties.enabled, emailReceivers = properties.emailReceivers"
                    $entry.description = "List action groups"
                } else {
                    $entry.queryable = $true
                    $entry.query = "resources | where type =~ 'microsoft.insights/metricalerts' or type =~ 'microsoft.insights/activitylogalerts' | project id, name, type, location, enabled = properties.enabled, description = properties.description"
                    $entry.description = "List metric and activity log alerts"
                }
                break
            }
            'backup' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.recoveryservices/vaults' | project id, name, location, sku = sku.name, properties"
                $entry.description = "List Recovery Services vaults for backup"
                break
            }
            'update management|patch' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.compute/virtualmachines' | project id, name, location, osType = properties.storageProfile.osDisk.osType, patchMode = properties.osProfile.windowsConfiguration.patchSettings.patchMode"
                $entry.description = "List VMs with patch management settings"
                break
            }
            
            # Compute
            'virtual machine|vm' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.compute/virtualmachines' | project id, name, location, vmSize = properties.hardwareProfile.vmSize, provisioningState = properties.provisioningState"
                $entry.description = "List all virtual machines"
                break
            }
            'availability zone' {
                $entry.queryable = $true
                $entry.query = "resources | where zones != '' | project id, name, type, location, zones"
                $entry.description = "List resources deployed to availability zones"
                break
            }
            'availability set' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.compute/availabilitysets' | project id, name, location, platformFaultDomainCount = properties.platformFaultDomainCount, platformUpdateDomainCount = properties.platformUpdateDomainCount"
                $entry.description = "List availability sets"
                break
            }
            
            # Organization
            'resource group' {
                $entry.queryable = $true
                $entry.query = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups' | project id, name, location, tags"
                $entry.description = "List all resource groups"
                break
            }
            'subscription' {
                $entry.queryable = $true
                $entry.query = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project id, name, subscriptionId, state = properties.state"
                $entry.description = "List all subscriptions"
                break
            }
            'management group' {
                $entry.queryable = $true
                $entry.query = "resourcecontainers | where type =~ 'microsoft.management/managementgroups' | project id, name, displayName = properties.displayName, tenantId = properties.tenantId"
                $entry.description = "List all management groups"
                break
            }
            'tag' {
                $entry.queryable = $true
                $entry.query = "resources | where isnull(tags) or array_length(todynamic(tags)) == 0 | project id, name, type, location, tags"
                $entry.description = "Find resources without tags"
                break
            }
            'naming convention|naming standard' {
                $entry.queryable = $true
                $entry.query = "resources | project id, name, type, location | take 100"
                $entry.description = "Sample resources to validate naming conventions (partial check)"
                break
            }
            
            # Advisor
            'recommendation|best practice' {
                if ($text -notmatch 'document|define|establish') {
                    $entry.queryable = $true
                    $entry.query = "advisorresources | where type =~ 'microsoft.advisor/recommendations' | project id, category = properties.category, impact = properties.impact, shortDescription = properties.shortDescription.solution, resourceId = properties.resourceMetadata.resourceId"
                    $entry.description = "List Azure Advisor recommendations"
                }
                break
            }
            
            # Containers
            'aks|kubernetes|azure kubernetes' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.containerservice/managedclusters' | project id, name, location, kubernetesVersion = properties.kubernetesVersion, networkProfile = properties.networkProfile.networkPlugin"
                $entry.description = "List AKS clusters with version"
                break
            }
            'container registry|acr' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.containerregistry/registries' | project id, name, location, sku = sku.tier, adminUserEnabled = properties.adminUserEnabled"
                $entry.description = "List container registries"
                break
            }
            
            # Databases
            'sql|database' {
                if ($text -match 'azure sql') {
                    $entry.queryable = $true
                    $entry.query = "resources | where type =~ 'microsoft.sql/servers/databases' | project id, name, location, sku = sku.name, maxSizeBytes = properties.maxSizeBytes"
                    $entry.description = "List Azure SQL databases"
                } elseif ($text -match 'cosmos') {
                    $entry.queryable = $true
                    $entry.query = "resources | where type =~ 'microsoft.documentdb/databaseaccounts' | project id, name, location, consistencyPolicy = properties.consistencyPolicy, enableMultipleWriteLocations = properties.enableMultipleWriteLocations"
                    $entry.description = "List Cosmos DB accounts"
                }
                break
            }
            
            # Monitoring
            'monitor|monitoring' {
                $entry.queryable = $true
                $entry.query = "resources | where type =~ 'microsoft.insights/diagnosticsettings' | summarize count() by tostring(split(id, '/providers/microsoft.insights/diagnosticSettings/')[0])"
                $entry.description = "Count diagnostic settings by resource"
                break
            }
            
            # Regions/Locations
            'region|location|geo' {
                if ($text -match 'multiple region|multi-region|secondary region') {
                    $entry.queryable = $true
                    $entry.query = "resources | summarize count() by location | order by count_ desc"
                    $entry.description = "Count resources by region to identify multi-region deployments"
                }
                break
            }
        }
    }
    
    # Final fallback - try to determine based on category and whether it mentions Azure resources
    if (-not $entry.queryable -and $entry.reason -eq "") {
        if ($text -match 'resource|azure|subscription|management group') {
            # Might be partially queryable
            $entry.queryable = $true
            $entry.query = "resources | where tags contains '$($item.subcategory)' or resourceGroup contains '$($item.subcategory)' | project id, name, type, location"
            $entry.description = "Generic query - may need customization (partial validation possible)"
        } else {
            $entry.queryable = $false
            $entry.reason = "Organizational/process requirement - not directly queryable via ARG"
        }
    }
    
    $output += $entry
}

# Convert to JSON and save
$output | ConvertTo-Json -Depth 10 | Set-Content "C:\git\alz-graph-queries\queries\alz_additional_queries.json" -Encoding UTF8

# Generate summary
$queryableCount = ($output | Where-Object { $_.queryable }).Count
$nonQueryableCount = ($output | Where-Object { -not $_.queryable }).Count

Write-Host "`n=== SUMMARY ==="
Write-Host "Total items processed: $($output.Count)"
Write-Host "Queryable items: $queryableCount"
Write-Host "Non-queryable items: $nonQueryableCount"
Write-Host "`nBreakdown by category:"
$output | Group-Object category | Sort-Object Name | ForEach-Object {
    $cat = $_.Name
    $queryable = ($_.Group | Where-Object { $_.queryable }).Count
    $total = $_.Count
    Write-Host "  $cat : $queryable/$total queryable"
}
