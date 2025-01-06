targetScope = 'subscription'

// ================ //
// Parameters       //
// ================ //

@maxLength(10)
@description('suffix (max 10 characters long) that will be used to name the resources in a pattern like <resourceAbbreviation>-<workloadName>')
param workloadName string = 'appsvc${take( uniqueString( subscription().id), 4) }'

@description('Azure region where the resources will be deployed in')
param location string = deployment().location

@description('Required. The name of the environmentName (e.g. "dev", "test", "prod", "preprod", "staging", "uat", "dr", "qa"). Up to 8 characters long.')
@maxLength(8)
param environmentName string = 'test'

@description('Optional, default is false. Set to true if you want to deploy ASE v3 instead of Multitenant App Service Plan.')
param deployAseV3 bool = false

@description('CIDR of the SPOKE vnet i.e. 192.168.0.0/24')
param vnetSpokeAddressSpace string = '10.240.0.0/20'

@description('CIDR of the subnet that will hold the app services plan. ATTENTION: ASEv3 needs a /24 network')
param subnetSpokeAppSvcAddressSpace string = '10.240.0.0/26'

@description('CIDR of the subnet that will hold devOps agents etc ')
param subnetSpokeDevOpsAddressSpace string = '10.240.10.128/26'

@description('CIDR of the subnet that will hold the private endpoints of the supporting services')
param subnetSpokePrivateEndpointAddressSpace string = '10.240.11.0/24'

@description('Default is empty. If empty, then a new hub will be created. If given, no new hub will be created and we create the  peering between spoke and and existing hub vnet')
param vnetHubResourceId string = ''

@description('Internal IP of the Azure firewall deployed in Hub. Used for creating UDR to route all vnet egress traffic through Firewall. If empty no UDR')
param firewallInternalIp string = ''

@description('The size of the jump box virtual machine to create. See https://learn.microsoft.com/azure/virtual-machines/sizes for more information.')
param vmSize string

@description('Defines the name, tier, size, family and capacity of the App Service Plan. Plans ending to _AZ, are deploying at least three instances in three Availability Zones. EP* is only for functions')
@allowed([
  'S1'
  'S2'
  'S3'
  'P1V3'
  'P2V3'
  'P3V3'
  'EP1'
  'EP2'
  'EP3'
  'ASE_I1V2'
  'ASE_I2V2'
  'ASE_I3V2'
])
param webAppPlanSku string = 'P1V3'

@description('Kind of server OS of the App Service Plan')
@allowed(['Windows', 'Linux'])
param webAppBaseOs string = 'Windows'

@description('mandatory, the username of the admin user of the jumpbox VM')
param adminUsername string = 'azureuser'

@description('mandatory, the password of the admin user of the jumpbox VM ')
@secure()
param adminPassword string

@description('set to true if you want to intercept all outbound traffic with azure firewall')
param enableEgressLockdown bool = false

@description('set to true if you want to deploy a jumpbox/devops VM')
param deployJumpHost bool = true

@description('Required. The SSH public key to use for the virtual machine.')
@secure()
param vmLinuxSshAuthorizedKey string = ''

@description('Optional. Type of authentication to use on the Virtual Machine. SSH key is recommended. Default is "password".')
@allowed([
  'sshPublicKey'
  'password'
])
param vmAuthenticationType string = 'password'

@description('Optional. The resource ID of the bastion host. If set, the spoke virtual network will be peered with the hub virtual network and the bastion host will be allowed to connect to the jump box. Default is empty.')
param bastionResourceId string = ''

param tags object = {}

@description('Optional. Enable/Disable usage telemetry for module.')
param enableTelemetry bool = true

param autoApproveAfdPrivateEndpoint bool = true

var resourceSuffix = '${workloadName}-${environmentName}-${location}'
var resourceGroupName = 'rg-spoke-${resourceSuffix}'

module resourceGroup 'br/public:avm/res/resources/resource-group:0.4.0' = {
  name: 'resourceGroupModule-Deployment1'
  params: {
    name: resourceGroupName
    location: location
  }
}

module naming './modules/naming/naming.module.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: 'NamingDeployment'
  params: {
    location: location
    suffix: [
      environmentName
    ]
    uniqueLength: 6
    uniqueSeed: resourceGroup.outputs.resourceId
  }
}

module spoke './modules/spoke/deploy.spoke.bicep' = {
  name: 'spokeDeployment'
  params: {
    naming: naming.outputs.names
    enableTelemetry: enableTelemetry
    resourceGroupName: resourceGroup.outputs.name
    location: location
    vnetSpokeAddressSpace: vnetSpokeAddressSpace
    subnetSpokeAppSvcAddressSpace: subnetSpokeAppSvcAddressSpace
    subnetSpokePrivateEndpointAddressSpace: subnetSpokePrivateEndpointAddressSpace
    subnetSpokeDevOpsAddressSpace: subnetSpokeDevOpsAddressSpace
    vnetHubResourceId: vnetHubResourceId
    firewallInternalIp: firewallInternalIp
    deployAseV3: deployAseV3
    webAppPlanSku: webAppPlanSku
    webAppBaseOs: webAppBaseOs
    adminUsername: adminUsername
    adminPassword: adminPassword
    enableEgressLockdown: enableEgressLockdown
    autoApproveAfdPrivateEndpoint: autoApproveAfdPrivateEndpoint
    deployJumpHost: deployJumpHost
    vmAdminUsername: adminUsername
    vmAdminPassword: adminPassword
    vmSize: vmSize
    bastionResourceId: bastionResourceId
    vmLinuxSshAuthorizedKey: vmLinuxSshAuthorizedKey
    vmAuthenticationType: vmAuthenticationType
    tags: tags
  }
}

module supportingServices './modules/supporting-services/deploy.supporting-services.bicep' = {
  name: 'supportingServicesDeployment'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    enableTelemetry: enableTelemetry
    naming: naming.outputs.names
    location: location
    spokeVNetId: spoke.outputs.vnetSpokeId
    spokePrivateEndpointSubnetName: spoke.outputs.spokePrivateEndpointSubnetName
    appServiceManagedIdentityPrincipalId: spoke.outputs.appServiceManagedIdentityPrincipalId
    hubVNetId: vnetHubResourceId
    tags: tags
  }
}