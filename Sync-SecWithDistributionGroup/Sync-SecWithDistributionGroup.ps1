<#
Version: 1.0
Author: Jannik Reinhard (jannikreinhard.com)
Script: Sync-DistributionGroupWithSecurityGroup
Description:
Sync a distribution group with an security group
Release notes:
Version 1.0: Init
#> 
Function Get-AuthHeader{
    param (
        [parameter(Mandatory=$true)]$tenantId,
        [parameter(Mandatory=$true)]$clientId,
        [parameter(Mandatory=$true)]$clientSecret
       )
    
    $authBody=@{
        client_id=$clientId
        client_secret=$clientSecret
        scope="https://graph.microsoft.com/.default"
        grant_type="client_credentials"
    }

    $uri="https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
    $accessToken=Invoke-WebRequest -Uri $uri -ContentType "application/x-www-form-urlencoded" -Body $authBody -Method Post -ErrorAction Stop -UseBasicParsing
    $accessToken=$accessToken.content | ConvertFrom-Json

    $authHeader = @{
        'Content-Type'='application/json'
        'Authorization'="Bearer " + $accessToken.access_token
        'ExpiresOn'=$accessToken.expires_in
    }
    
    return $authHeader
}

function Get-GraphCall {
    param(
        [Parameter(Mandatory)]
        $apiUri
    )
    return Invoke-RestMethod -Uri https://graph.microsoft.com/beta/$apiUri -Headers $authToken -Method GET
}

#### Start#####

# Variables
$tenantId = Get-AutomationVariable -Name 'TenantId'
$clientId = Get-AutomationVariable -Name 'AppId'
$clientSecret = Get-AutomationVariable -Name 'AppSecret'

$certAppId = "CLIENTIDCERT"
$certThumprint = "THETHUMBPRINTOFTHE CERT"
$organisation = "YOURORGNAME.onmicrosoft.com"

$secGroupId = 'ID OF THE SEC GROUP'
$distGroupName = 'DIST GROUP NAME'


# Authentication
$global:authToken = Get-AuthHeader -tenantId $tenantId -clientId $clientId -clientSecret $clientSecret
Connect-ExchangeOnline -CertificateThumbPrint $certThumprint -AppID $certAppId -Organization $organisation

# Check if group exist
try {
    if(-not (Get-DistributionGroup | Where-Object{$_.DisplayName -eq $distGroupName})){
        Write-Error "Distribution group $distGroupName not found"
        return
    }
}catch{
    Write-Error "$_"
    return
}


# Get sec group member
try{
    $secGroupMember = (Get-GraphCall -apiUri "groups/$secGroupId/members").value
}catch{
    Write-Error "Failed to get member of security group $secGroupId : $_"
}

# Get distribution group member
try{
    $distributionGroupMember = Get-DistributionGroupMember -Identity $distGroupName
}catch{
    Write-Error "Failed to get member of distribution group $secGroupId : $_"
}

# Get member to add and delete
$toDelete = $distributionGroupMember | Where {$_.name -notin $secGroupMember.mailNickname}
$toAdd = $secGroupMember | Where {$_.mailNickname -notin $distributionGroupMember.name} 


# Add to distribution group
$toAdd | ForEach-Object {
    try{
        Add-DistributionGroupMember $distGroupName -Member $_.userPrincipalName
        Write-Host "Sucessfully add $($_.userPrincipalName) to distribution group"
    }catch{
        Write-Error "Failed to add member $($_.userPrincipalName): $_"
    }
}

# Delete from distribution group
$toDelete | ForEach-Object {
    try{
        Remove-DistributionGroupMember $distGroupName -Member $_.Name -Confirm:$false
        Write-Host "Sucessfully remove $($_.Name) from distribution group"
    }catch{
        Write-Error "Failed to delete member $($_.userPrincipalName): $_"
    }
}

