@description('The name of the Administrator of the new VM and Domain')
param adminUsername string

@description('The password for the Administrator account of the new VM and Domain')
@secure()
param adminPassword string

@description('The FQDN of the AD Domain created ')
param domainName string

@description('The DNS prefix for the public IP address used by the Load Balancer')
param dnsPrefix string

@description('The public RDP port for the PDC VM')
param pdcRDPPort int = 3389

@description('The public RDP port for the BDC VM')
param bdcRDPPort int = 13389

@description('The location of resources, such as templates and DSC modules, that the template depends on')
param _artifactsLocation string = deployment().properties.templateLink.uri

@description('Auto-generated token to access _artifactsLocation')
@secure()
param _artifactsLocationSasToken string = ''

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Size for the VM.  This sample uses premium disk and requires an \'S\' sku.')
param adVMSize string = 'Standard_D2s_v3'

var storageAccountType = 'Premium_LRS'
var adPDCVMName = 'adPDC'
var adBDCVMName = 'adBDC'
var imagePublisher = 'MicrosoftWindowsServer'
var imageOffer = 'WindowsServer'
var imageSKU = '2016-Datacenter'
var adAvailabilitySetName = 'adAvailabiltySet'
var publicIPAddressName = 'ad-lb-pip'
var adLBFE = 'LBFE'
var adLBBE = 'LBBE'
var adPDCRDPNAT = 'adPDCRDP'
var adBDCRDPNAT = 'adBDCRDP'
var virtualNetworkName = 'adVNET'
var virtualNetworkAddressRange = '10.0.0.0/16'
var adSubnetName = 'adSubnet'
var adSubnet = '10.0.0.0/24'
var adPDCNicName = 'adPDCNic'
var adPDCNicIPAddress = '10.0.0.4'
var adBDCNicName = 'adBDCNic'
var adBDCNicIPAddress = '10.0.0.5'
var adSubnetRef = resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, adSubnetName)
var adLBName = 'adLoadBalancer'
var adlbFEConfigID = resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', adLBName, adLBFE)
var adPDCRDPNATRuleID = resourceId('Microsoft.Network/loadBalancers/inboundNatRules', adLBName, adPDCRDPNAT)
var adBDCRDPNATRuleID = resourceId('Microsoft.Network/loadBalancers/inboundNatRules', adLBName, adBDCRDPNAT)
var adBEAddressPoolID = resourceId('Microsoft.Network/loadBalancers/backendAddressPools', adLBName, adLBBE)
var adDataDiskSize = 1000
var vnetTemplateUri = uri(_artifactsLocation, 'nestedtemplates/vnet.json${_artifactsLocationSasToken}')
var nicTemplateUri = uri(_artifactsLocation, 'nestedtemplates/nic.json${_artifactsLocationSasToken}')
var vnetwithDNSTemplateUri = uri(_artifactsLocation, 'nestedtemplates/vnet-with-dns-server.json${_artifactsLocationSasToken}')
var configureADBDCTemplateUri = uri(_artifactsLocation, 'nestedtemplates/configureADBDC.json${_artifactsLocationSasToken}')
var adPDCModulesURL = uri(_artifactsLocation, 'DSC/CreateADPDC.zip${_artifactsLocationSasToken}')
var adPDCConfigurationFunction = 'CreateADPDC.ps1\\CreateADPDC'
var adBDCPreparationModulesURL = uri(_artifactsLocation, 'DSC/PrepareADBDC.zip${_artifactsLocationSasToken}')
var adBDCPreparationFunction = 'PrepareADBDC.ps1\\PrepareADBDC'
var adBDCConfigurationModulesURL = uri(_artifactsLocation, 'DSC/ConfigureADBDC.zip${_artifactsLocationSasToken}')
var adBDCConfigurationFunction = 'ConfigureADBDC.ps1\\ConfigureADBDC'

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2020-03-01' = {
  name: publicIPAddressName
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: dnsPrefix
    }
  }
}

resource adAvailabilitySet 'Microsoft.Compute/availabilitySets@2019-12-01' = {
  location: location
  name: adAvailabilitySetName
  properties: {
    platformUpdateDomainCount: 20
    platformFaultDomainCount: 2
  }
  sku: {
    name: 'Aligned'
  }
}

module VNet '?' /*TODO: replace with correct path to [variables('vnetTemplateUri')]*/ = {
  name: 'VNet'
  params: {
    location: location
    virtualNetworkName: virtualNetworkName
    virtualNetworkAddressRange: virtualNetworkAddressRange
    subnetName: adSubnetName
    subnetRange: adSubnet
  }
}

resource adLB 'Microsoft.Network/loadBalancers@2020-03-01' = {
  name: adLBName
  location: location
  properties: {
    frontendIPConfigurations: [
      {
        name: adLBFE
        properties: {
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: adLBBE
      }
    ]
    inboundNatRules: [
      {
        name: adPDCRDPNAT
        properties: {
          frontendIPConfiguration: {
            id: adlbFEConfigID
          }
          protocol: 'Tcp'
          frontendPort: pdcRDPPort
          backendPort: 3389
          enableFloatingIP: false
        }
      }
      {
        name: adBDCRDPNAT
        properties: {
          frontendIPConfiguration: {
            id: adlbFEConfigID
          }
          protocol: 'Tcp'
          frontendPort: bdcRDPPort
          backendPort: 3389
          enableFloatingIP: false
        }
      }
    ]
  }
}

resource adPDCNic 'Microsoft.Network/networkInterfaces@2020-03-01' = {
  name: adPDCNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: adPDCNicIPAddress
          subnet: {
            id: adSubnetRef
          }
          loadBalancerBackendAddressPools: [
            {
              id: adBEAddressPoolID
            }
          ]
          loadBalancerInboundNatRules: [
            {
              id: adPDCRDPNATRuleID
            }
          ]
        }
      }
    ]
  }
  dependsOn: [
    VNet
    adLB
  ]
}

resource adBDCNic 'Microsoft.Network/networkInterfaces@2020-03-01' = {
  name: adBDCNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: adBDCNicIPAddress
          subnet: {
            id: adSubnetRef
          }
          loadBalancerBackendAddressPools: [
            {
              id: adBEAddressPoolID
            }
          ]
          loadBalancerInboundNatRules: [
            {
              id: adBDCRDPNATRuleID
            }
          ]
        }
      }
    ]
  }
  dependsOn: [
    VNet
    adLB
  ]
}

resource adPDCVM 'Microsoft.Compute/virtualMachines@2019-12-01' = {
  name: adPDCVMName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: adVMSize
    }
    availabilitySet: {
      id: adAvailabilitySet.id
    }
    osProfile: {
      computerName: adPDCVMName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSKU
        version: 'latest'
      }
      osDisk: {
        name: '${adPDCVMName}_OSDisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: storageAccountType
        }
      }
      dataDisks: [
        {
          name: '${adPDCVMName}_data-disk1'
          caching: 'None'
          diskSizeGB: adDataDiskSize
          lun: 0
          createOption: 'Empty'
          managedDisk: {
            storageAccountType: storageAccountType
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: adPDCNic.id
        }
      ]
    }
  }
  dependsOn: [

    adLB
  ]
}

resource adPDCVMName_CreateADForest 'Microsoft.Compute/virtualMachines/extensions@2019-12-01' = {
  parent: adPDCVM
  name: 'CreateADForest'
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.19'
    autoUpgradeMinorVersion: true
    settings: {
      ModulesUrl: adPDCModulesURL
      ConfigurationFunction: adPDCConfigurationFunction
      Properties: {
        type: 'string'
        DomainName: domainName
        AdminCreds: {
          UserName: adminUsername
          Password: 'PrivateSettingsRef:AdminPassword'
        }
      }
    }
    protectedSettings: {
      Items: {
        AdminPassword: adminPassword
      }
    }
  }
}

module UpdateVNetDNS1 '?' /*TODO: replace with correct path to [variables('vnetwithDNSTemplateUri')]*/ = {
  name: 'UpdateVNetDNS1'
  params: {
    location: location
    virtualNetworkName: virtualNetworkName
    virtualNetworkAddressRange: virtualNetworkAddressRange
    subnetName: adSubnetName
    subnetRange: adSubnet
    DNSServerAddress: [
      adPDCNicIPAddress
    ]
  }
  dependsOn: [
    adPDCVMName_CreateADForest
  ]
}

module UpdateBDCNIC '?' /*TODO: replace with correct path to [variables('nicTemplateUri')]*/ = {
  name: 'UpdateBDCNIC'
  params: {
    location: location
    nicName: adBDCNicName
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: adBDCNicIPAddress
          subnet: {
            id: adSubnetRef
          }
          loadBalancerBackendAddressPools: [
            {
              id: adBEAddressPoolID
            }
          ]
          loadBalancerInboundNatRules: [
            {
              id: adBDCRDPNATRuleID
            }
          ]
        }
      }
    ]
    dnsServers: [
      adPDCNicIPAddress
    ]
  }
  dependsOn: [
    adBDCNic
    UpdateVNetDNS1
  ]
}

resource adBDCVM 'Microsoft.Compute/virtualMachines@2019-12-01' = {
  name: adBDCVMName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: adVMSize
    }
    availabilitySet: {
      id: adAvailabilitySet.id
    }
    osProfile: {
      computerName: adBDCVMName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSKU
        version: 'latest'
      }
      osDisk: {
        name: '${adBDCVMName}_osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: storageAccountType
        }
      }
      dataDisks: [
        {
          name: '${adBDCVMName}_data-disk1'
          caching: 'None'
          diskSizeGB: adDataDiskSize
          lun: 0
          createOption: 'Empty'
          managedDisk: {
            storageAccountType: storageAccountType
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: adBDCNic.id
        }
      ]
    }
  }
  dependsOn: [

    adLB
  ]
}

resource adBDCVMName_PrepareBDC 'Microsoft.Compute/virtualMachines/extensions@2019-12-01' = {
  parent: adBDCVM
  name: 'PrepareBDC'
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.19'
    autoUpgradeMinorVersion: true
    settings: {
      ModulesUrl: adBDCPreparationModulesURL
      ConfigurationFunction: adBDCPreparationFunction
      Properties: {
        DNSServer: adPDCNicIPAddress
      }
    }
  }
}

module ConfiguringBackupADDomainController '?' /*TODO: replace with correct path to [variables('configureADBDCTemplateUri')]*/ = {
  name: 'ConfiguringBackupADDomainController'
  params: {
    adBDCVMName: adBDCVMName
    location: location
    adminUsername: adminUsername
    adminPassword: adminPassword
    domainName: domainName
    adBDCConfigurationFunction: adBDCConfigurationFunction
    adBDCConfigurationModulesURL: adBDCConfigurationModulesURL
  }
  dependsOn: [
    adBDCVMName_PrepareBDC
    UpdateBDCNIC
  ]
}

module UpdateVNetDNS2 '?' /*TODO: replace with correct path to [variables('vnetwithDNSTemplateUri')]*/ = {
  name: 'UpdateVNetDNS2'
  params: {
    location: location
    virtualNetworkName: virtualNetworkName
    virtualNetworkAddressRange: virtualNetworkAddressRange
    subnetName: adSubnetName
    subnetRange: adSubnet
    DNSServerAddress: [
      adPDCNicIPAddress
      adBDCNicIPAddress
    ]
  }
  dependsOn: [
    ConfiguringBackupADDomainController
  ]
}