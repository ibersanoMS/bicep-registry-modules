@description('Required. Name of the AFD profile.')
param afdName string

@description('Name of the endpoint under the profile which is unique globally.')
param endpointName string

@allowed([
  'Enabled'
  'Disabled'
])
@description('AFD Endpoint State')
param endpointEnabled string = 'Enabled'

@description('Optional. Endpoint tags.')
param tags object = {}

@allowed([
  'Standard_AzureFrontDoor'
  'Premium_AzureFrontDoor'
])
@description('Required. The pricing tier (defines a CDN provider, feature list and rate) of the CDN profile.')
param skuName string

// @description('Custom Domain List')
// param customDomains array

@description('The name of the Origin Group')
param originGroupName string

@description('Origin List')
param origins array

@description('Optional, default value false. Set true if you need to cache content at the AFD level')
param enableCaching bool = false

@description('Name of the WAF policy to create.')
@maxLength(128)
param wafPolicyName string

@allowed([
  'Block'
  'Log'
  'Redirect'
])
param wafRuleSetAction string = 'Log'

@description('optional, default value Enabled. ')
@allowed([
  'Enabled'
  'Disabled'
])
param wafPolicyState string = 'Enabled'

@description('optional, default value Prevention. ')
@allowed([
  'Detection'
  'Prevention'
])
param wafPolicyMode string = 'Prevention'

// Create an Array of all Endpoint which includes customDomain Id and afdEndpoint Id
// This array is needed to be attached to Microsoft.Cdn/profiles/securitypolicies
// var customDomainIds = [for (domain, index) in customDomains: {id: custom_domains[index].id}]
// var afdEndpointIds = [{id: endpoint.id}]
// var endPointIdsForWaf = union(customDomainIds, afdEndpointIds)
//var endPointIdsForWaf = [{ id: endpoint.id }]

@description('Default Content to compress')
var contentTypeCompressionList = [
  'application/eot'
  'application/font'
  'application/font-sfnt'
  'application/javascript'
  'application/json'
  'application/opentype'
  'application/otf'
  'application/pkcs7-mime'
  'application/truetype'
  'application/ttf'
  'application/vnd.ms-fontobject'
  'application/xhtml+xml'
  'application/xml'
  'application/xml+rss'
  'application/x-font-opentype'
  'application/x-font-truetype'
  'application/x-font-ttf'
  'application/x-httpd-cgi'
  'application/x-javascript'
  'application/x-mpegurl'
  'application/x-opentype'
  'application/x-otf'
  'application/x-perl'
  'application/x-ttf'
  'font/eot'
  'font/ttf'
  'font/otf'
  'font/opentype'
  'image/svg+xml'
  'text/css'
  'text/csv'
  'text/html'
  'text/javascript'
  'text/js'
  'text/plain'
  'text/richtext'
  'text/tab-separated-values'
  'text/xml'
  'text/x-script'
  'text/x-component'
  'text/x-java-source'
]

module waf 'br/public:avm/res/network/front-door-web-application-firewall-policy:0.3.0' = {
  name: wafPolicyName
  params: {
    name: 'waffrontdoor'
    location: 'Global'
    sku: skuName
    policySettings: {
      enabledState: wafPolicyState
      mode: wafPolicyMode
      requestBodyCheck: 'Enabled'
    }
    customRules: {
      rules: [
        {
          name: 'BlockMethod'
          enabledState: 'Enabled'
          action: 'Block'
          ruleType: 'MatchRule'
          priority: 10
          rateLimitDurationInMinutes: 1
          rateLimitThreshold: 100
          matchConditions: [
            {
              matchVariable: 'RequestMethod'
              operator: 'Equal'
              negateCondition: true
              matchValue: [
                'GET'
                'OPTIONS'
                'HEAD'
              ]
            }
          ]
        }
      ]
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: wafRuleSetAction
          ruleGroupOverrides: []
        }
      ]
    }
  }
}

module frontDoor 'br/public:avm/res/cdn/profile:0.7.0' = {
  name: afdName
  params: {
    name: afdName
    sku: skuName
    location: 'global'
    originResponseTimeoutSeconds: 120
    afdEndpoints: [
      {
        name: endpointName
        enabledState: endpointEnabled
        cacheConfiguration: !enableCaching
          ? null
          : {
              dynamicCompression: 'Enabled'
              queryStringsCachingBehavior: 'IgnoreQueryString'
              dynamicCompressionLevel: 'Normal'
              queryStringCachingBehavior: 'UseQueryString'
              contentTypesToCompress: contentTypeCompressionList
            }
        routes: [
          {
            name: '${originGroupName}-route'
            originGroupName: originGroupName
            patternsToMatch: [
              '/*'
            ]
            forwardingProtocol: 'HttpsOnly'
            linkToDefaultDomain: 'Enabled'
            httpsRedirect: 'Enabled'
            enabledState: 'Enabled'
          }
        ]
        tags: tags
      }
    ]
    originGroups: [
      {
        name: originGroupName
        loadBalancingSettings: {
          sampleSize: 4
          successfulSamplesRequired: 3
          additionalLatencyInMilliseconds: 50
        }
        healthProbeSettings: {
          probePath: '/'
          probeRequestType: 'GET'
          probeProtocol: 'Https'
          probeIntervalInSeconds: 100
        }
        sessionAffinityState: 'Disabled'
        trafficRestorationTimeToHealedOrNewEndpointsInMinutes: 10
        origins: [
          for (origin, index) in origins: {
            name: replace(origin.hostname, '.', '-')
            hostName: origin.hostname
            httpPort: 80
            httpsPort: 443
            priority: 1
            weight: 1000
            enabledState: origin.enabledState ? 'Enabled' : 'Disabled'
            enforceCertificateNameCheck: true
            privateLinkOrigin: empty(origin.privateLinkOrigin)
              ? null
              : {
                  privateEndpointResourceId: origin.privateLinkOrigin.privateEndpointResourceId
                  privateLinkResourceType: origin.privateLinkOrigin.privateLinkResourceType
                  privateEndpointLocation: origin.privateLinkOrigin.privateEndpointLocation
                }
          }
        ]
      }
    ]

    securityPolicies: [
      {
        name: 'webApplicationFirewall'
        wafPolicyResourceId: waf.outputs.resourceId
        associations: [
          {
            domains: [
              {
                id: resourceId(
                  subscription().subscriptionId,
                  resourceGroup().name,
                  'Microsoft.Cdn/profiles/afdEndpoints',
                  afdName,
                  '${endpointName}'
                )
              }
            ]
            patternsToMatch: [
              '/*'
            ]
          }
        ]
      }
    ]
  }
}

@description('The name of the CDN profile.')
output afdProfileName string = frontDoor.outputs.name

@description('The resource ID of the CDN profile.')
output afdProfileId string = frontDoor.outputs.resourceId

@description('Name of the endpoint.')
output endpointName string = frontDoor.outputs.endpointName

@description('HostName of the endpoint.')
output afdEndpointHostName string = frontDoor.outputs.uri

@description('The resource group where the CDN profile is deployed.')
output resourceGroupName string = resourceGroup().name

@description('The type of the CDN profile.')
output profileType string = frontDoor.outputs.profileType