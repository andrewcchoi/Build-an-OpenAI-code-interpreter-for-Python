targetScope = 'resourceGroup'

var openAIAccountName = 'openai-${uniqueString(resourceGroup().id)}'
var azureOpenAIRegion = 'canadaeast'

var searchServiceName = 'search-${uniqueString(resourceGroup().id)}'
var acrName = 'acr${uniqueString(resourceGroup().id)}'
var logAnalyticsWorkspaceName = 'loganalytics-${uniqueString(resourceGroup().id)}'
var acaEnvName = 'env-${uniqueString(resourceGroup().id)}'
var sessionPoolName = 'sessionpool-${uniqueString(resourceGroup().id)}'

resource openAIAccount 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: openAIAccountName
  location: azureOpenAIRegion
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  properties: {
    publicNetworkAccess: 'Enabled'
    customSubDomainName: openAIAccountName
  }
}

resource ada002 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = {
  parent: openAIAccount
  name: 'text-embedding-ada-002'
  sku: {
    name: 'Standard'
    capacity: 150
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-ada-002'
      version: '2'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    currentCapacity: 150
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}


resource aiSearch 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchServiceName
  location: resourceGroup().location
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'Enabled'
    networkRuleSet: {
      ipRules: []
      bypass: 'None'
    }
    disableLocalAuth: false
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    disabledDataExfiltrationOptions: []
    semanticSearch: 'free'
  }
  sku: {
    name: 'basic'
  }
}



resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  sku: {
    name: 'Standard'
  }
  name: acrName
  location: resourceGroup().location
  tags: {}
  properties: {
    adminUserEnabled: false
    policies: {
      azureADAuthenticationAsArmPolicy: {
        status: 'enabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    anonymousPullEnabled: false
    metadataSearch: 'Enabled'
  }
}


resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: resourceGroup().location
  properties: any({
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
  })
}


resource env 'Microsoft.App/managedEnvironments@2024-02-02-preview' = {
  name: acaEnvName
  location: resourceGroup().location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
         workloadProfileType: 'Consumption'
      }
    ]
  }
  identity: {
    type: 'SystemAssigned'
  }
}

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
resource acrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, acrPullRoleId, env.id)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: env.identity.principalId
    principalType: 'ServicePrincipal'
  }
}


resource sessionPool 'Microsoft.App/sessionPools@2024-02-02-preview' = {
  name: sessionPoolName
  location: 'North Central US'
  properties: {
    poolManagementType: 'Dynamic'
    containerType: 'PythonLTS'
    scaleConfiguration: {
      maxConcurrentSessions: 50
    }
    dynamicPoolConfiguration: {
      executionType: 'Timed'
      cooldownPeriodInSeconds: 300
    }
    sessionNetworkConfiguration: {
      status: 'EgressDisabled'
    }
  }
}


module chatApp 'container-app.bicep' = {
  name: 'container-app'
  params: {
    envId: env.id
    searchEndpoint: 'https://${aiSearch.name}.search.windows.net'
    openAIEndpoint: openAIAccount.properties.endpoint
    sessionPoolEndpoint: sessionPool.properties.poolManagementEndpoint
    acrServer: registry.properties.loginServer
  }
}

var sessionExecutorRoleId = '0fb8eba5-a2bb-4abe-b1c1-49dfad359bb0'
resource sessionExecutorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sessionPool.id, sessionExecutorRoleId, resourceGroup().id, 'chatapp')
  scope: sessionPool
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sessionExecutorRoleId)
    principalId: chatApp.outputs.chatApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}


