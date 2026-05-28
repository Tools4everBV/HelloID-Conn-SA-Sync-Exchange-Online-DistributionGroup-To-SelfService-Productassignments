| :information_source: Information                                                                                                                                                                                                                                                                                                                                                       |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |
<br />

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-SA-Sync-Exchange-Online-DistributionGroup-To-SelfService-Productassignments/blob/main/Logo.png?raw=true">
</p>

<!-- TABLE OF CONTENTS -->
## Table of Contents
- [Table of Contents](#table-of-contents)
- [Introduction](#introduction)
- [Getting started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Connection settings](#connection-settings)
- [Remarks](#remarks)
- [Getting help](#getting-help)
- [HelloID Docs](#helloid-docs)

## Introduction
By using this connector, you will have the ability to create and remove HelloID SelfService Productassignments based on groupmemberships in your Exchange Online Distribution Groups.

The products will be assigned to a user when they are already a member of the group that the product would make them member of. This way the product can be returned to revoke the groupmembership without having to first request all the products "you already have".

And vice versa for the removing of the productassignments. The products will be returned from a user when they are already no longer a member of the group that the product would make them member of. This way the product can be requested again without having to first return all the products "you already no longer have".

This is intended for scenarios where the groupmemberships are managed by other sources (e.g. manual actions or Provisioning) than the HelloID products to keep this in sync. This groupmembership sync is desinged to work in combination with the [Exchange Oniline Distribution Groups to Products Sync](https://github.com/Tools4everBV/HelloID-Conn-SA-Sync-Exchange-Online-DistributionGroup-To-SelfService-Products).

## Getting started

### Prerequisites
- [ ] Installed and available [Microsoft Exchange Online PowerShell V3 module](https://www.powershellgallery.com/packages/ExchangeOnlineManagement)
- [ ] To manage users, mailboxes and groups, the service account has to have the role "**Exchange Recipient Administrator**" assigned.
- [ ] Required to run **On-Premises** since it is not allowed to import a module with the Cloud Agent.
- [ ] Define the Global variables for your Exchange Environment

### Connection settings

The connection settings are defined in the automation variables [user defined variables](https://docs.helloid.com/hc/en-us/articles/360014169933-How-to-Create-and-Manage-User-Defined-Variables). And the Product configuration can be configured in the script


| Variable name                   | Description                                                                                                                  | Notes                                                                                                                                                                                                                                                                                                      |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| $portalBaseUrl                  | HelloID Base Url                                                                                                             | (Default Global Variable)                                                                                                                                                                                                                                                                                  |
| $portalApiKey                   | HelloID Api Key                                                                                                              | (Default Global Variable)                                                                                                                                                                                                                                                                                  |
| $portalApiSecret                | HelloID Api Secret                                                                                                           | (Default Global Variable)                                                                                                                                                                                                                                                                                  |
| $EntraIdOrganization            | The Entra ID Organization yourCompany.onmicrosoft.com                                                                        | Recommended to set as Global Variable                                                                                                                                                                                                                                                                      |
| $EntraIdAppId                   | String value of Entra ID App ID                                                                                              | Recommended to set as Global Variable                                                                                                                                                                                                                                                                      |
| $EntraIdCertificateBase64String | Base64 string of Entra ID App Certificate                                                                                    | Recommended to set as Global Variable                                                                                                                                                                                                                                                                      |
| $EntraIdCertificatePassword     | Password of Entra ID App Certificate                                                                                         | Recommended to set as Global Variable                                                                                                                                                                                                                                                                      |
| $exchangeGroupsFilter           | String value of seachfilter of which Exchange Online groups to include                                                       | Optional, when no filter is provided ($exchangeGroupsFilter = $null), all groups will be queried - Only displayName and description are supported with the search filter. Reference: https://learn.microsoft.com/en-us/graph/search-query-parameter?tabs=http#using-search-on-directory-object-collections |
| $ProductSkuPrefix               | String value of prefix filter of which HelloID Self service Products to include                                              | Optional, when no SkuPrefix is provided ($ProductSkuPrefix = $null), all products will be queried                                                                                                                                                                                                          |
| $PowerShellActionName           | String value of name of the PowerShell action that grants the Exchange Online user to the Exchange Online Distribution Group | The default value ("Grant-PermissionToDistributionGroup") is set to match the value from the [Exchange Oniline Distribution Groups to Products Sync](https://github.com/Tools4everBV/HelloID-Conn-SA-Sync-Exchange-Online-DistributionGroup-To-SelfService-Products)                                       |
| $exoUserCorrelationProperty     | String value of name of the property of Exchange Online users to match to HelloID users                                      | The default value ("userPrincipalName") is set to match the value from the [Exchange Oniline Distribution Groups to Products Sync](https://github.com/Tools4everBV/HelloID-Conn-SA-Sync-Exchange-Online-DistributionGroup-To-SelfService-Products)                                                         |
| $helloIDUserCorrelationProperty | String value of name of the property of HelloID users to match to Exchange Online users                                      | The default value ("username") is set to match the value from the [Entra ID Sync](https://docs.helloid.com/en/access-management/directory-sync/azure-ad-sync.html                                                                                                                                          |

## Remarks
- The Productassignments are granted and revoked. Make sure your configuration is correct to avoid unwanted revokes
- This groupmembership sync is designed to work in combination with the [Exchange Oniline Distribution Groups to Products Sync](https://github.com/Tools4everBV/HelloID-Conn-SA-Sync-Exchange-Online-DistributionGroup-To-SelfService-Products). If your products are from a different source, this sync task might not work and needs changes accordingly.

## Getting help
> _For more information on how to configure a HelloID PowerShell scheduled task, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/115003253294-Create-Custom-Scheduled-Tasks) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID Docs
The official HelloID documentation can be found at: https://docs.helloid.com/