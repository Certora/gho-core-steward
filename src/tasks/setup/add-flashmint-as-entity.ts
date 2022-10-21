import { task } from 'hardhat/config';
import { DRE, impersonateAccountHardhat } from '../../helpers/misc-utils';
import { aaveMarketAddresses } from '../../helpers/config';
import { ghoEntityConfig } from '../../helpers/config';
import { IGhoToken } from '../../../types/src/contracts/gho/interfaces/IGhoToken';
import { getAaveProtocolDataProvider } from '@aave/deploy-v3/dist/helpers/contract-getters';

task('add-flashmint-as-entity', 'Adds Flashminter as a gho entity').setAction(async (_, hre) => {
  await hre.run('set-DRE');
  const { ethers } = DRE;

  let gho = await ethers.getContract('GhoToken');
  let flashMint = await ethers.getContract('FlashMinter');

  const aaveDataProvider = await getAaveProtocolDataProvider();
  const tokenProxyAddresses = await aaveDataProvider.getReserveTokensAddresses(gho.address);

  const governanceSigner = await impersonateAccountHardhat(aaveMarketAddresses.shortExecutor);
  gho = await gho.connect(governanceSigner);

  const aaveEntity: IGhoToken.FacilitatorStruct = {
    label: ghoEntityConfig.label,
    bucket: {
      maxCapacity: ghoEntityConfig.mintLimit,
      level: 0,
    },
  };

  const addEntityTx = await gho.addFacilitators([flashMint.address], [aaveEntity]);
  const addEntityTxReceipt = await addEntityTx.wait();

  let error = false;
  if (addEntityTxReceipt && addEntityTxReceipt.events) {
    const newEntityEvents = addEntityTxReceipt.events.filter((e) => e.event === 'FacilitatorAdded');
    if (newEntityEvents.length > 0) {
      console.log(
        `Address FlashMint added as a facilitator: ${JSON.stringify(newEntityEvents[0].args[0])}`
      );
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
