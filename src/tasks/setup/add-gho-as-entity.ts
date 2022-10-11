import { task } from 'hardhat/config';
import { DRE, impersonateAccountHardhat } from '../../helpers/misc-utils';
import { aaveMarketAddresses } from '../../helpers/config';
import { ghoEntityConfig } from '../../helpers/config';
import { IGhoToken } from '../../../types/src/contracts/gho/interfaces/IGhoToken';
import { getAaveProtocolDataProvider } from '@aave/deploy-v3/dist/helpers/contract-getters';
import { getNetwork } from '../../helpers/misc-utils';

task('add-gho-as-entity', 'Adds Aave as a gho entity').setAction(async (_, hre) => {
  await hre.run('set-DRE');
  const { ethers } = DRE;

  let gho = await ethers.getContract('GhoToken');

  const aaveDataProvider = await getAaveProtocolDataProvider();
  const tokenProxyAddresses = await aaveDataProvider.getReserveTokensAddresses(gho.address);

  // const network = getNetwork();
  // const { shortExecutor } = aaveMarketAddresses[network];
  // const governanceSigner = await impersonateAccountHardhat(shortExecutor);

  const [_deployer] = await hre.ethers.getSigners();

  gho = await gho.connect(_deployer);

  const aaveEntity: IGhoToken.FacilitatorStruct = {
    label: ghoEntityConfig.label,
    bucket: {
      maxCapacity: ghoEntityConfig.mintLimit,
      level: 0,
    },
  };

  const addEntityTx = await gho.addFacilitators([tokenProxyAddresses.aTokenAddress], [aaveEntity]);
  const addEntityTxReceipt = await addEntityTx.wait();

  let error = false;
  if (addEntityTxReceipt && addEntityTxReceipt.events) {
    const newEntityEvents = addEntityTxReceipt.events.filter((e) => e.event === 'FacilitatorAdded');
    if (newEntityEvents.length > 0) {
      console.log(`Address added as a facilitator: ${JSON.stringify(newEntityEvents[0].args[0])}`);
    } else {
      error = true;
    }
  } else {
    error = true;
  }
  if (error) {
    console.log(`ERROR: Aave not added as GHO entity`);
  }
});
