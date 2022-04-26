import { task } from 'hardhat/config';
import { DRE, impersonateAccountHardhat } from '../../helpers/misc-utils';
import { ZERO_ADDRESS } from '../../helpers/constants';
import { aaveMarketAddresses } from '../../helpers/config';
import { getAToken, getAaveProtocolDataProvider } from '../../helpers/contract-getters';
import { asdEntityConfig } from '../../helpers/config';

task('add-asd-as-entity', 'Adds Aave as a asd entity').setAction(async (_, hre) => {
  await hre.run('set-DRE');
  const { ethers } = DRE;

  let asd = await ethers.getContract('AnteiStableDollarEntities');

  const aaveDataProvider = await getAaveProtocolDataProvider(
    aaveMarketAddresses.aaveProtocolDataProvider
  );

  const tokenProxyAddresses = await aaveDataProvider.getReserveTokensAddresses(asd.address);
  const aToken = await getAToken(tokenProxyAddresses.aTokenAddress);
  const variableDebtToken = await getAToken(tokenProxyAddresses.variableDebtTokenAddress);

  const governanceSigner = await impersonateAccountHardhat(aaveMarketAddresses.shortExecutor);
  asd = await asd.connect(governanceSigner);

  const addEntityTx = await asd.addEntities([aToken.address], [asdEntityConfig.mintLimit]);
  const addEntityTxReceipt = await addEntityTx.wait();

  let error = false;
  if (addEntityTxReceipt && addEntityTxReceipt.events) {
    const newEntityEvents = addEntityTxReceipt.events.filter((e) => e.event === 'EntityCreated');
    if (newEntityEvents.length > 0) {
      console.log(`New Entity Added with ID ${newEntityEvents[0].args.id}`);
    } else {
      error = true;
    }
  } else {
    error = true;
  }
  if (error) {
    console.log(`ERROR: Aave not added as ASD entity`);
  }
});
