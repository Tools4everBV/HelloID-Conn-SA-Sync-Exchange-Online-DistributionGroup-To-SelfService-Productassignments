#####################################################
# HelloID-Conn-SA-Sync-Exchange-Online-DistributionGroup-To-HelloID-Selfservice-Productassignments
#
# Version: 1.1.0
#####################################################
# Set to false to acutally perform actions - Only run as DryRun when testing/troubleshooting!
$dryRun = $false
# Set to true to log each individual action - May cause lots of logging, so use with cause, Only run testing/troubleshooting!
$verboseLogging = $false

switch ($verboseLogging) {
    $true { $VerbosePreference = "Continue" }
    $false { $VerbosePreference = "SilentlyContinue" }
}
$informationPreference = "Continue"
$WarningPreference = "Continue"

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Make sure to create the Global variables defined below in HelloID
#HelloID Connection Configuration
# $script:PortalBaseUrl = "" # Set from Global Variable
# $portalApiKey = "" # Set from Global Variable
# $portalApiSecret = "" # Set from Global Variable

# Exchange Online connection (required)
# $EntraIdOrganization = "" # Set from Global Variable
# $EntraIdAppId = "" # Set from Global Variable
# $EntraIdCertificateBase64String = "" # Set from Global Variable
# $EntraIdCertificatePassword = "" # Set from Global Variable

$exchangeGroupsFilter = "DisplayName -like 'DistributionGroup*'" # Optional, when no filter is provided ($exchangeGroupsFilter = $null), all distribution group will be queried

# PowerShell commands to import
$commands = @(
    "Get-User"
    , "Get-DistributionGroup"
    , "Get-DistributionGroupMember"
) # Fixed list of commands required by script - only change when missing commands

#HelloID Self service Product Configuration
$ProductSkuPrefix = 'EXOGRP' # Optional, when no SkuPrefix is provided ($ProductSkuPrefix = $null), all products will be queried
$PowerShellActionName = "Grant-PermissionToDistributionGroup" # Define the name of the PowerShell action

#Correlation Configuration
# The name of the property of HelloID users to match to EXO users - value has to match the value of the property specified in $exoUserCorrelationProperty
$helloIDUserCorrelationProperty = "username"
# The name of the property of EXO users to match to HelloID users - value has to match the value of the property specified in $helloIDUserCorrelationProperty
$exoUserCorrelationProperty = "userPrincipalName"

#region functions

function Remove-StringLatinCharacters {
    PARAM ([string]$String)
    [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes($String))
}

function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ""
        }

        if ($ErrorObject.Exception.GetType().FullName -eq "Microsoft.PowerShell.Commands.HttpResponseException") {
            # $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message # Does not show the correct error message for the Raet IAM API calls
            $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message

        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq "System.Net.WebException") {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }

        Write-Output $httpErrorObj
    }
}

function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if ( $($ErrorObject.Exception.GetType().FullName -eq "Microsoft.PowerShell.Commands.HttpResponseException") -or $($ErrorObject.Exception.GetType().FullName -eq "System.Net.WebException")) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage

            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}

function Invoke-HIDRestmethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [Parameter(Mandatory = $false)]
        $PageSize,

        [string]
        $ContentType = "application/json"
    )

    try {
        Write-Verbose "Switching to TLS 1.2"
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

        Write-Verbose "Setting authorization headers"
        $apiKeySecret = "$($portalApiKey):$($portalApiSecret)"
        $base64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($apiKeySecret))
        $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
        $headers.Add("Authorization", "Basic $base64")
        $headers.Add("Content-Type", $ContentType)
        $headers.Add("Accept", $ContentType)

        $splatWebRequest = @{
            Uri             = "$($script:PortalBaseUrl)/api/v1/$($Uri)"
            Headers         = $headers
            Method          = $Method
            UseBasicParsing = $true
            ErrorAction     = "Stop"
        }
        
        if (-not[String]::IsNullOrEmpty($PageSize)) {
            $data = [System.Collections.ArrayList]@()

            $skip = 0
            $take = $PageSize
            Do {
                $splatWebRequest["Uri"] = "$($script:PortalBaseUrl)/api/v1/$($Uri)?skip=$($skip)&take=$($take)"

                Write-Verbose "Invoking [$Method] request to [$Uri]"
                $response = $null
                $response = Invoke-RestMethod @splatWebRequest -Verbose:$false
                if (($response.PsObject.Properties.Match("pageData") | Measure-Object).Count -gt 0) {
                    $dataset = $response.pageData
                }
                else {
                    $dataset = $response
                }

                if ($dataset -is [array]) {
                    [void]$data.AddRange($dataset)
                }
                else {
                    [void]$data.Add($dataset)
                }
            
                $skip += $take
            }until(($dataset | Measure-Object).Count -ne $take)

            return $data
        }
        else {
            if ($Body) {
                Write-Verbose "Adding body to request"
                $splatWebRequest["Body"] = ([System.Text.Encoding]::UTF8.GetBytes($body))
            }

            Write-Verbose "Invoking [$Method] request to [$Uri]"
            $response = $null
            $response = Invoke-RestMethod @splatWebRequest -Verbose:$false

            return $response
        }

    }
    catch {
        throw $_
    }
}

function Get-MSEntraCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificateBase64String,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificatePassword
    )
    try {
        $rawCertificate = [system.convert]::FromBase64String($CertificateBase64String)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        Write-Output $certificate
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion functions

#region script
Hid-Write-Status -Event Information -Message "Starting synchronization of Exchange Online Users from Distribution Groups to HelloID Groupmemberships"
Hid-Write-Status -Event Information -Message "------[HelloID]------"
#region Get HelloID Products
try {
    Write-Verbose "Querying Self service products from HelloID"

    $splatParams = @{
        Method = "GET"
        Uri    = "selfservice/products"
    }
    $helloIDSelfServiceProducts = Invoke-HIDRestMethod @splatParams

    # Filter for products with specified Sku Prefix
    if (-not[String]::IsNullOrEmpty($ProductSkuPrefix)) {
        $helloIDSelfServiceProductsInScope = $null
        $helloIDSelfServiceProductsInScope = $helloIDSelfServiceProducts | Where-Object { $_.code -like "$ProductSkuPrefix*" }
    }
    else {
        $helloIDSelfServiceProductsInScope = $null
        $helloIDSelfServiceProductsInScope = $helloIDSelfServiceProducts
    }

    Hid-Write-Status -Event Success -Message "Successfully queried Self service products from HelloID (after filtering for products with specified sku prefix only). Result count: $(($helloIDSelfServiceProductsInScope | Measure-Object).Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Hid-Write-Status -Event Error -Message "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

    throw "Error querying Self service products from HelloID. Error Message: $($errorMessage.AuditErrorMessage)"
}
#endregion Get HelloID Products

#region Get HelloID Users
try {
    Write-Verbose "Querying Users from HelloID"

    $splatWebRequest = @{
        Method   = "GET"
        Uri      = "users"
        PageSize = 1000
    }
    $helloIDUsers = Invoke-HIDRestMethod @splatWebRequest

    # $helloIDUsersGroupedOnUserName = $helloIDUsers | Group-Object -Property "userName" -AsHashTable -AsString
    # $helloIDUsersGroupedOnUserGUID = $helloIDUsers | Group-Object -Property "userGUID" -AsHashTable -AsString
    $helloIDUsersGrouped = $helloIDUsers | Group-Object -Property $helloIDUserCorrelationProperty -AsHashTable -AsString

    Hid-Write-Status -Event Success -Message "Successfully queried Users from HelloID. Result count: $(($helloIDUsers | Measure-Object).Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Hid-Write-Status -Event Error -Message "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

    throw "Error querying Users from HelloID. Error Message: $($errorMessage.AuditErrorMessage)"
}
#endregion Get HelloID Users

#region Get actions of Product
try {
    [System.Collections.ArrayList]$helloIDSelfServiceProductsInScopeWithActions = @()
    Write-Verbose "Querying HelloID Self service Products with Actions"
    foreach ($helloIDSelfServiceProductInScope in $helloIDSelfServiceProductsInScope) {
        #region Get objects with Distribution Group
        try {
            $helloIDSelfServiceProductInScopeWithActionsObject = [PSCustomObject]@{
                productId   = $helloIDSelfServiceProductInScope.selfServiceProductGUID
                name        = $helloIDSelfServiceProductInScope.name
                description = $helloIDSelfServiceProductInScope.description
                code        = $helloIDSelfServiceProductInScope.code
                actions     = [System.Collections.ArrayList]@()
            }

            Write-Verbose "Querying actions of Product [$($helloIDSelfServiceProductInScope.selfServiceProductGUID)]"

            $splatParams = @{
                Method = "GET"
                Uri    = "products/$($helloIDSelfServiceProductInScope.selfServiceProductGUID)"
            }
            $helloIDSelfServiceProduct = Invoke-HIDRestMethod @splatParams

            # Add actions of all "grant" states
            $helloIDSelfServiceProductActions = $helloIDSelfServiceProduct.onRequest + $helloIDSelfServiceProduct.onApprove
            foreach ($helloIDSelfServiceProductAction in $helloIDSelfServiceProductActions) {
                $helloIDSelfServiceProductActionObject = [PSCustomObject]@{
                    actionGUID = $helloIDSelfServiceProductAction.actionGUID
                    name       = $helloIDSelfServiceProductAction.name
                    objectGUID = $helloIDSelfServiceProductAction.objectGUID
                }

                [void]$helloIDSelfServiceProductInScopeWithActionsObject.actions.Add($helloIDSelfServiceProductActionObject)
            }

            [void]$helloIDSelfServiceProductsInScopeWithActions.Add($helloIDSelfServiceProductInScopeWithActionsObject)

            if ($verboseLogging -eq $true) {
                Write-Verbose "Successfully queried actions of Product [$($helloIDSelfServiceProductInScope.selfServiceProductGUID)]. Result count: $(($helloIDSelfServiceProduct.actions | Measure-Object).Count)"
            }
        }
        catch {
            $ex = $PSItem
            $errorMessage = Get-ErrorMessage -ErrorObject $ex
        
            Hid-Write-Status -Event Error -Message "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"
        
            throw "Error querying actions of Product [$($helloIDSelfServiceProductInScope.productId)]. Error Message: $($errorMessage.AuditErrorMessage)"
        }
        #endregion Get objects Distribution Group
    }

    # Filter for products with specified actions
    $helloIDSelfServiceProductsInScopeWithActionsInScope = $helloIDSelfServiceProductsInScopeWithActions | Where-Object { $PowerShellActionName -in $_.actions.name }

    Hid-Write-Status -Event Success -Message "Successfully queried HelloID Self service Products with Actions (after filtering for products with specified action only). Result count: $(($helloIDSelfServiceProductsInScopeWithActionsInScope.actions | Measure-Object).Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Hid-Write-Status -Event Error -Message "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

    throw "Error querying HelloID Self service Products with Actions. Error Message: $($errorMessage.AuditErrorMessage)"
}
#endregion Get actions of Product

#region Get HelloID Productassignments
try {
    Write-Verbose "Querying  Self service Productassignments from HelloID"

    $splatParams = @{
        Method   = "GET"
        Uri      = "product-assignment"
        PageSize = 1000
    }
    $helloIDSelfServiceProductassignments = Invoke-HIDRestMethod @splatParams

    # Filter for for productassignments of specified products
    $helloIDSelfServiceProductassignmentsInScope = $null
    $helloIDSelfServiceProductassignmentsInScope = $helloIDSelfServiceProductassignments | Where-Object { $_.productGuid -in $helloIDSelfServiceProductsInScopeWithActionsInScope.productId }

    $helloIDSelfServiceProductassignmentsInScopeGrouped = $helloIDSelfServiceProductassignmentsInScope | Group-Object -Property productGuid -AsHashTable -AsString
    Hid-Write-Status -Event Success -Message "Successfully queried Self service Productassignments from HelloID (after filtering for productassignments of specified products only). Result count: $(($helloIDSelfServiceProductassignmentsInScope | Measure-Object).Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Hid-Write-Status -Event Error -Message "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

    throw "Error querying Self service Productassignments from HelloID. Error Message: $($errorMessage.AuditErrorMessage)"
}
#endregion Get HelloID Productassignments

Hid-Write-Status -Event Information -Message "------[Exchange Online]-----------"

# Import module
try {    
    $actionMessage = "importing module [ExchangeOnlineManagement]"
    $importModuleSplatParams = @{
        Name        = "ExchangeOnlineManagement"
        Cmdlet      = $commands
        Verbose     = $false
        ErrorAction = "Stop"
    }
    $null = Import-Module @importModuleSplatParams

    #region Retrieving certificate
    $actionMessage = "retrieving certificate"
    $certificate = Get-MSEntraCertificate -CertificateBase64String $EntraIdCertificateBase64String -CertificatePassword $EntraIdCertificatePassword
    #endregion Retrieving certificate
    
    #region Connect to Microsoft Exchange Online
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/connect-exchangeonline?view=exchange-ps
    $actionMessage = "connecting to Microsoft Exchange Online"
    $createExchangeSessionSplatParams = @{
        Organization          = $EntraIdOrganization
        AppID                 = $EntraIdAppId
        Certificate           = $certificate
        CommandName           = $commands
        ShowBanner            = $false
        ShowProgress          = $false
        TrackPerformance      = $false
        SkipLoadingCmdletHelp = $true
        SkipLoadingFormatData = $true
        ErrorAction           = "Stop"
    }
    $null = Connect-ExchangeOnline @createExchangeSessionSplatParams
    Write-Information "Connected to Microsoft Exchange Online"
} 
catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)"        
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    Hid-Write-Status -Event Error -Message $warningMessage
    Hid-Write-Status -Event Error -Message $auditMessage
    throw $auditMessage
}

#region Get Exchange Online Distribution Groups
# Get Exchange Online Distribution Groups
try {  
    $exchangeQuerySplatParams = @{
        Filter      = $exchangeGroupsFilter
        ResultSize  = "Unlimited"
        Verbose     = $false
        ErrorAction = "Stop"
    }

    Hid-Write-Status -Event Information -Message "Querying Exchange Online Distribution Groups that match filter [$($exchangeQuerySplatParams.Filter)]"
    $exoGroups = Get-DistributionGroup @exchangeQuerySplatParams

    if (($exoGroups | Measure-Object).Count -eq 0) {
        throw "No Distribution Groups have been found"
    }

    Hid-Write-Status -Event Success -Message "Successfully queried Exchange Online Distribution Groups. Result count: $(($exoGroups | Measure-Object).Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Hid-Write-Status -Event Error -Message "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

    throw "Error querying Exchange Online Distribution Groups that match filter [$($exchangeQuerySplatParams.Filter)]. Error Message: $($errorMessage.AuditErrorMessage)"
}
#endregion Get Exchange Online Distribution Groups

#region Get Exchange online users
# Exchange Online users are needed so all the attributes are available
try {
    Write-Verbose "Querying Exchange users"

    $exoUsers = Get-User -ResultSize Unlimited -Verbose:$false

    if (($exoUsers | Measure-Object).Count -eq 0) {
        throw "No Users have been found"
    }

    $exoUsersGroupedOnGuid = $exoUsers | Group-Object Guid -AsHashTable -AsString
    Hid-Write-Status -Event Success -Message "Successfully queried Exchange Online Users. Result count: $(($exoUsers | Measure-Object).Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Hid-Write-Status -Event Error -Message "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

    throw "Error querying all Exchange users. Error Message: $($errorMessage.AuditErrorMessage)"
}
#endregion Get Exchange online users

#region Get permissions to Distribution Groups
try {
    [System.Collections.ArrayList]$exoGroupsUserMembers = @()
    Write-Verbose "Querying Exchange Distribution Groups Members"
    foreach ($exoGroup in $exoGroups) {
        #region Get objects with Distribution Groups Members
        try {
            $exoGroupWithUsersObject = [PSCustomObject]@{
                DisplayName       = $exoGroup.DisplayName
                Name              = $exoGroup.Name
                UserPrincipalName = $exoGroup.UserPrincipalName
                Id                = $exoGroup.Id
                Guid              = $exoGroup.Guid
                Users             = [System.Collections.ArrayList]@()
            }

            Write-Verbose "Querying Members of Distribution Group [$($exoGroup.Guid)]"

            $groupMembers = Get-DistributionGroupMember -Identity $exoGroup.Guid -ResultSize Unlimited -Verbose:$false # Returns UPN of users, DisplayName of groups

            # Filter out UserMailbox
            $groupMembers = $groupMembers | Where-Object { ($_.RecipientType -eq 'UserMailbox') }

            foreach ($groupMember in $groupMembers) {
                $groupUser = $null
                # list of al the users in the distribution group. This includes the groups member from the distribution group
                if ($null -ne $groupMember) {
                    $groupUser = $null
                    $groupUser = $exoUsersGroupedOnGuid["$($groupMember.Guid)"]
                    if ($null -ne $groupUser) {
                        $userObject = [PSCustomObject]@{
                            Id                = $groupUser.id
                            DisplayName       = $groupUser.displayName
                            UserPrincipalName = $groupUser.userPrincipalName
                        }

                        [void]$exoGroupWithUsersObject.Users.Add($userObject)
                    }
                }
            }

            [void]$exoGroupsUserMembers.Add($exoGroupWithUsersObject)

            if ($verboseLogging -eq $true) {
                Write-Verbose "Successfully queried Distribution Group [$($exoGroup.DisplayName)] [$($exoGroup.Guid)]. Result count: $(($groupMembers | Measure-Object).Count)"
            }
        }
        catch {
            $ex = $PSItem
            $errorMessage = Get-ErrorMessage -ErrorObject $ex
        
            Hid-Write-Status -Event Error -Message "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"
        
            throw "Error querying Distribution Group [$($exoGroup.DisplayName)] [$($exoGroup.Guid)] Error Message: $($errorMessage.AuditErrorMessage)"
        }
        #endregion Get objects Distribution Group
    }
    $exoGroupsUserMembersGrouped = $exoGroupsUserMembers | Group-Object -Property guid -AsHashTable -AsString

    Hid-Write-Status -Event Success -Message "Successfully queried Distribution Groups. Result count: $(($exoGroupsUserMembers.Users | Measure-Object).Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Hid-Write-Status -Event Error -Message "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

    throw "Error querying Distribution Groups. Error Message: $($errorMessage.AuditErrorMessage)"
}
#endregion Get permissions to Distribution Group

Hid-Write-Status -Event Information -Message "------[Calculations of combined data]------"
# Calculate new and obsolete product assignments
try {
    $newProductAssignmentObjects = [System.Collections.ArrayList]@()
    $obsoleteProductAssignmentObjects = [System.Collections.ArrayList]@()
    $existingProductAssignmentObjects = [System.Collections.ArrayList]@()
    foreach ($product in $helloIDSelfServiceProductsInScopeWithActionsInScope) {
        # if ($verboseLogging -eq $true) {
        #     Write-Verbose "Calculating new and obsolete product assignments for Product [$($product.name)]"
        # }

        # Get Group from Product Action
        $exoGroupGuid = [Guid]::New(($product.code.replace("$ProductSkuPrefix", "")))
        $exoGroup = $null
        $exoGroup = $exoGroupsUserMembersGrouped["$($exoGroupGuid)"]
        if (($exoGroup | Measure-Object).Count -eq 0) {
            Hid-Write-Status -Event Error -Message "No Exchange Online distribution groups found with Guid [$($exoGroupGuid)] for Product [$($product.name)]"
            continue
        }
        elseif (($exoGroup | Measure-Object).Count -gt 1) {
            Hid-Write-Status -Event Error -Message "Multiple Exchange Online distribution groups found with Guid [$($exoGroupGuid)] for Product [$($product.name)]"
            continue
        }

        # Get EXO user objects for additional data to match to HelloID user
        $exoUsersInScope = $exoGroup.Users
        
        # Get HelloID user objects to assign to the product
        $productUsersInScope = [System.Collections.ArrayList]@()
        foreach ($exoUser in $exoUsersInScope) {
            $helloIDUser = $null
            $helloIDUser = $helloIDUsersGrouped["$($exoUser.$exoUserCorrelationProperty)"]

            if (($helloIDUser | Measure-Object).Count -eq 0) {
                if ($verboseLogging -eq $true) {
                    Write-Verbose "No HelloID user found with $helloIDUserCorrelationProperty [$($exoUser.$exoUserCorrelationProperty)] for EXO user [$($exoUser.Id)] for Product [$($product.name)]"
                }
            }
            else {
                [void]$productUsersInScope.Add($helloIDUser)
            }
        }

        # Get current product assignments
        $currentProductassignments = $null
        if (($helloIDSelfServiceProductassignmentsInScope | Measure-Object).Count -ge 1) {
            $currentProductassignments = $helloIDSelfServiceProductassignmentsInScopeGrouped["$($product.productId)"]
        }

        # Define assignments to grant
        $newProductassignments = $productUsersInScope | Where-Object { $_.userGuid -notin $currentProductassignments.userGuid }
        foreach ($newProductAssignment in $newProductassignments) {
            $newProductAssignmentObject = [PSCustomObject]@{
                productGuid            = "$($product.productId)"
                productName            = "$($product.name)"
                userGuid               = "$($newProductAssignment.userGuid)"
                userName               = "$($newProductAssignment.userName)"
                source                 = "SyncEXODistributionGroupPermissionsToProductAssignments"
                executeApprovalActions = $false
            }

            [void]$newProductAssignmentObjects.Add($newProductAssignmentObject)
        }

        # Define assignments to revoke
        $obsoleteProductassignments = $currentProductassignments | Where-Object { $_.userGuid -notin $productUsersInScope.userGuid }
        foreach ($obsoleteProductassignment in $obsoleteProductassignments) { 
            $obsoleteProductAssignmentObject = [PSCustomObject]@{
                productGuid            = "$($product.productId)"
                productName            = "$($product.name)"
                userGuid               = "$($obsoleteProductassignment.userGuid)"
                userName               = "$($obsoleteProductassignment.userName)"
                source                 = "SyncEXODistributionGroupPermissionsToProductAssignments"
                executeApprovalActions = $false
            }
    
            [void]$obsoleteProductAssignmentObjects.Add($obsoleteProductAssignmentObject)
        }

        # Define assignments already existing
        $existingProductassignments = $currentProductassignments | Where-Object { $_.userGuid -in $productUsersInScope.userGuid }
        foreach ($existingProductassignment in $existingProductassignments) { 
            $existingProductAssignmentObject = [PSCustomObject]@{
                productGuid            = "$($product.productId)"
                productName            = "$($product.name)"
                userGuid               = "$($existingProductassignment.userGuid)"
                userName               = "$($existingProductassignment.userName)"
                source                 = "SyncEXOFullAccessPermissionsToProductAssignments"
                executeApprovalActions = $false
            }
    
            [void]$existingProductAssignmentObjects.Add($existingProductAssignmentObject)
        }

        # Define total assignments (existing + new assignments)
        $totalProductAssignments = ($(($existingProductAssignmentObjects | Measure-Object).Count) + $(($newProductAssignmentObjects | Measure-Object).Count))
    }
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Hid-Write-Status -Event Error -Message "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

    throw "Error calculating new and obsolete product assignments. Error Message: $($errorMessage.AuditErrorMessage)"
}

Hid-Write-Status -Event Information -Message "------[Summary]------"

Hid-Write-Status -Event Information -Message "Total HelloID Self service Product(s) in scope [$(($helloIDSelfServiceProductsInScope | Measure-Object).Count)]"

Hid-Write-Status -Event Information -Message "Total HelloID Self service Productassignment(s) already exist (and won't be changed) [$(($existingProductAssignmentObjects | Measure-Object).Count)]"

Hid-Write-Status -Event Information -Message "Total HelloID Self service Productassignment(s) to grant [$(($newProductAssignmentObjects | Measure-Object).Count)]"

Hid-Write-Status -Event Information -Message "Total HelloID Self service Productassignment(s) to revoke [$(($obsoleteProductAssignmentObjects | Measure-Object).Count)]"

Hid-Write-Status -Event Information -Message "------[Processing]------------------"
try {
    # Grant assignments
    $productAssigmentGrantsSuccess = 0
    $productAssigmentGrantsError = 0
    foreach ($newProductAssignmentObject in $newProductAssignmentObjects) {
        try {
            # if ($verboseLogging -eq $true) {
            #     Write-Verbose "Granting productassignment for HelloID user [$($newProductAssignmentObject.username) ($($newProductAssignmentObject.userGuid))] to HelloID Self service Product [$($newProductAssignmentObject.productName) ($($newProductAssignmentObject.productGuid))]""
            # }
        
            $body = @{
                userGuid               = "$($newProductAssignmentObject.userGuid)"
                source                 = "$($newProductAssignmentObject.source)"
                executeApprovalActions = $newProductAssignmentObject.executeApprovalActions
                comment                = "Synchronized assignment from EXO Distribution Group permissions"
            } | ConvertTo-Json

            $splatParams = @{
                Method      = "POST"
                Uri         = "product-assignment/$($newProductAssignmentObject.productGuid)"
                Body        = $body # ([System.Text.Encoding]::UTF8.GetBytes($body))
                ErrorAction = "Stop"
            }
            if ($dryRun -eq $false) {
                $grantProductassignmentToUser = Invoke-HIDRestMethod @splatParams
                if ($verboseLogging -eq $true) {
                    Write-Verbose "Successfully granted productassignment for HelloID user [$($newProductAssignmentObject.username) ($($newProductAssignmentObject.userGuid))] to HelloID Self service Product [$($newProductAssignmentObject.productName) ($($newProductAssignmentObject.productGuid))]"
                }
                $productAssigmentGrantsSuccess++
            }
            else {
                if ($verboseLogging -eq $true) {
                    Write-Verbose "DryRun: Would grant productassignment for HelloID user [$($newProductAssignmentObject.username) ($($newProductAssignmentObject.userGuid))] to HelloID Self service Product [$($newProductAssignmentObject.productName) ($($newProductAssignmentObject.productGuid))]"
                }   
            }
        }
        catch {
            $ex = $PSItem
            $errorMessage = Get-ErrorMessage -ErrorObject $ex
        
            Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"
        
            $productAssigmentGrantsError++
            if ($verboseLogging -eq $true) {
                Write-Verbose "Error granting productassignment for HelloID user [$($newProductAssignmentObject.username) ($($newProductAssignmentObject.userGuid))] to HelloID Self service Product [$($newProductAssignmentObject.productName) ($($newProductAssignmentObject.productGuid))]. Error Message: $($errorMessage.AuditErrorMessage)"
            }
        }
    }
    if ($dryRun -eq $false) {
        if ($productAssigmentGrantsSuccess -ge 1 -or $productAssigmentGrantsError -ge 1) {
            Hid-Write-Status -Event Information -Message "Granted productassignments to HelloID Self service Products. Success: $($productAssigmentGrantsSuccess). Error: $($productAssigmentGrantsError)"
            Hid-Write-Summary -Event Information -Message "Granted productassignments to HelloID Self service Products. Success: $($productAssigmentGrantsSuccess). Error: $($productAssigmentGrantsError)"
        }
    }
    else {
        Hid-Write-Status -Event Warning -Message "DryRun: Would grant [$(($newProductAssignmentObjects | Measure-Object).Count)] productassignments for [$(($newProductAssignmentObjects | Sort-Object -Property productGuid -Unique | Measure-Object).Count)] HelloID Self service Products"
        Hid-Write-Summary -Event Warning "DryRun: Would grant [$(($newProductAssignmentObjects | Measure-Object).Count)] productassignments for [$(($newProductAssignmentObjects | Sort-Object -Property productGuid -Unique | Measure-Object).Count)] HelloID Self service Products"
    }

    # Revoke assignments
    $productAssigmentRevokesSuccess = 0
    $productAssigmentRevokesError = 0
    foreach ($obsoleteProductAssignmentObject in $obsoleteProductAssignmentObjects) { 
        try {
            # if ($verboseLogging -eq $true) {
            #     Write-Verbose "Revoking productassignment for HelloID user [$($obsoleteProductAssignmentObject.username) ($($obsoleteProductAssignmentObject.userGuid))] to HelloID Self service Product [$($obsoleteProductAssignmentObject.productName) ($($obsoleteProductAssignmentObject.productGuid))]""
            # }
            
            $body = @{
                productGuid            = "$($obsoleteProductAssignmentObject.productGuid)"
                userGuid               = "$($obsoleteProductAssignmentObject.userGuid)"
                executeApprovalActions = $($obsoleteProductAssignmentObject.executeApprovalActions)
            } | ConvertTo-Json

            $splatParams = @{
                Method      = "POST"
                Uri         = "product-assignment/unassign/by-product"
                Body        = $body # ([System.Text.Encoding]::UTF8.GetBytes($body))
                ErrorAction = "Stop"
            }
            if ($dryRun -eq $false) {
                $revokeProductassignmentToUser = Invoke-HIDRestMethod @splatParams
                if ($verboseLogging -eq $true) {
                    Write-Verbose "Successfully revoked productassignment for HelloID user [$($obsoleteProductAssignmentObject.username) ($($obsoleteProductAssignmentObject.userGuid))] to HelloID Self service Product [$($obsoleteProductAssignmentObject.productName) ($($obsoleteProductAssignmentObject.productGuid))]"
                }
                $productAssigmentRevokesSuccess++
            }
            else {
                if ($verboseLogging -eq $true) {
                    Write-Verbose "DryRun: Would revoke productassignment for HelloID user [$($obsoleteProductAssignmentObject.username) ($($obsoleteProductAssignmentObject.userGuid))] to HelloID Self service Product [$($obsoleteProductAssignmentObject.productName) ($($obsoleteProductAssignmentObject.productGuid))]"
                }   
            }
        }
        catch {
            $ex = $PSItem
            $errorMessage = Get-ErrorMessage -ErrorObject $ex
            
            Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"
            
            $productAssigmentRevokesError++
            if ($verboseLogging -eq $true) {
                Write-Verbose "Error revoking productassignment for HelloID user [$($obsoleteProductAssignmentObject.username) ($($obsoleteProductAssignmentObject.userGuid))] to HelloID Self service Product [$($obsoleteProductAssignmentObject.productName) ($($obsoleteProductAssignmentObject.productGuid))]. Error Message: $($errorMessage.AuditErrorMessage)"
            }
        }
    }
    if ($dryRun -eq $false) {
        if ($productAssigmentRevokesSuccess -ge 1 -or $productAssigmentRevokesError -ge 1) {
            Hid-Write-Status -Event Information -Message "Revoked productassignments to HelloID Self service Products. Success: $($productAssigmentRevokesSuccess). Error: $($productAssigmentRevokesError)"
            Hid-Write-Summary -Event Information -Message "Revoked productassignments to HelloID Self service Products. Success: $($productAssigmentRevokesSuccess). Error: $($productAssigmentRevokesError)"
        }
    }
    else {
        Hid-Write-Status -Event Warning -Message "DryRun: Would revoke [$(($obsoleteProductassignmentObjects | Measure-Object).Count)] productassignments for [$(($obsoleteProductassignmentObjects | Sort-Object -Property productGuid -Unique | Measure-Object).Count)] HelloID Self service Products"
        Hid-Write-Status -Event Warning -Message "DryRun: Would revoke [$(($obsoleteProductassignmentObjects | Measure-Object).Count)] productassignments for [$(($obsoleteProductassignmentObjects | Sort-Object -Property productGuid -Unique | Measure-Object).Count)] HelloID Self service Products"
    }

    if ($dryRun -eq $false) {
        Hid-Write-Status -Event Success -Message "Successfully synchronized [$(($exoGroupsUserMembers.Users | Measure-Object).Count)] Exchange Online Distribution Groups to [$totalProductAssignments] HelloID Self service Productassignments for [$(($helloIDSelfServiceProductsInScope | Measure-Object).Count)] HelloID Self service Products"
        Hid-Write-Summary -Event Success -Message "Successfully synchronized [$(($exoGroupsUserMembers.Users | Measure-Object).Count)] Exchange Online Distribution Groups to [$totalProductAssignments] HelloID Self service Productassignments for [$(($helloIDSelfServiceProductsInScope | Measure-Object).Count)] HelloID Self service Products"
    }
    else {
        Hid-Write-Status -Event Success -Message "DryRun: Would synchronize [$(($exoGroupsUserMembers.Users | Measure-Object).Count)] Exchange Online Distribution Groups to [$totalProductAssignments] HelloID Self service Productassignments for [$(($helloIDSelfServiceProductsInScope | Measure-Object).Count)] HelloID Self service Products"
        Hid-Write-Summary -Event Success -Message "DryRun: Would synchronize [$(($exoGroupsUserMembers.Users | Measure-Object).Count)] Exchange Online Distribution Groups to [$totalProductAssignments] HelloID Self service Productassignments for [$(($helloIDSelfServiceProductsInScope | Measure-Object).Count)] HelloID Self service Products"
    }
}
catch {
    Hid-Write-Status -Event Error -Message "Error synchronization of [$(($exoGroupsUserMembers.Users | Measure-Object).Count)] Exchange Online Distribution Groups to [$totalProductAssignments] HelloID Self service Productassignments for [$(($helloIDSelfServiceProductsInScope | Measure-Object).Count)] HelloID Self service Products"
    Hid-Write-Status -Event Error -Message "Error at Line [$($_.InvocationInfo.ScriptLineNumber)]: $($_.InvocationInfo.Line)."
    Hid-Write-Status -Event Error -Message "Exception message: $($_.Exception.Message)"
    Hid-Write-Status -Event Error -Message "Exception details: $($_.errordetails)"
    Hid-Write-Summary -Event Failed -Message "Error synchronization of [$(($exoGroupsUserMembers.Users | Measure-Object).Count)] Exchange Online Distribution Groups to [$totalProductAssignments] HelloID Self service Productassignments for [$(($helloIDSelfServiceProductsInScope | Measure-Object).Count)] HelloID Self service Products"
}
#endregion
