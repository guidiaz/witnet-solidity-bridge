const addresses = require("../migrations/addresses.json")
const merge = require("lodash.merge")
const utils = require("./utils")
module.exports = {
  getAddresses: (network) => {
    const [eco, net] = utils.getRealmNetworkFromString(network)
    if (addresses[net]) {
      const merged = merge(
        addresses.default,
        addresses[eco],
        addresses[net],
      )
      return {
        WitnetPriceFeeds: merged?.WitnetPriceFeeds,
        WitnetRequestBoard: merged?.WitnetRequestBoard,
      }
    } else {
      return {}
    }
  },
  supportedEcosystems: () => {
    const ecosystems = []
    supportedNetworks().forEach(network => {
      const [ecosystem] = utils.getRealmNetworkFromString(network)
      if (!ecosystems.includes(ecosystem)) {
        ecosystems.push(ecosystem)
      }
    })
    return ecosystems
  },
  supportedNetworks,
  artifacts: {
    WitnetRequestBytecodes: require("../artifacts/contracts/WitnetRequestBytecodes.sol/WitnetRequestBytecodes.json"),
    WitnetPriceFeeds: require("../artifacts/contracts/apps/WitnetPriceFeeds.sol/WitnetPriceFeeds.json"),
    WitnetRequest: require("../artifacts/contracts/WitnetRequest.sol/WitnetRequest.json"),
    WitnetRequestBoard: require("../artifacts/contracts/WitnetRequestBoard.sol/WitnetRequestBoard.json"),
    WitnetRequestFactory: require("../artifacts/contracts/WitnetRequestFactory.sol/WitnetRequestFactory.json"),
    WitnetRequestTemplate: require("../artifacts/contracts/WitnetRequestTemplate.sol/WitnetRequestTemplate.json"),
    WitnetUpgradableBase: require("../artifacts/contracts/core/WitnetUpgradableBase.sol/WitnetUpgradableBase.json"),
    IWitnetPriceSolver: require("../artifacts/contracts/interfaces/V2/IWitnetPriceSolver.sol/IWitnetPriceSolver.json"),
  },
  settings: require("../settings"),
  utils,
}

function supportedNetworks (ecosystem) {
  return Object
    .entries(addresses)
    .filter(value => value[0].indexOf(":") > -1 && (!ecosystem || value[0].startsWith(ecosystem)))
    .map(value => value[0])
    .sort()
}
