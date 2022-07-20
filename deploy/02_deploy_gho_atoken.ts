import { DeployFunction } from 'hardhat-deploy/types';
import { aaveMarketAddresses } from '../src/helpers/config';
import { ghoTokenConfig } from '../src/helpers/config';
import { getUndeployedVariableDebtTokenProxyAddress } from './utils';

const func: DeployFunction = async function ({ getNamedAccounts, deployments, ...hre }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const { pool, treasury, incentivesController } = aaveMarketAddresses;
  const gho = await hre.ethers.getContract('GhoToken');

  const { TOKEN_NAME, TOKEN_SYMBOL } = ghoTokenConfig;

  const aTokenImplementation = await deploy('GhoAToken', {
    from: deployer,
    args: [
      pool,
      await getUndeployedVariableDebtTokenProxyAddress(),
      gho.address,
      treasury,
      TOKEN_NAME,
      TOKEN_SYMBOL,
      incentivesController,
    ],
  });

  console.log(`AToken Implementation:         ${aTokenImplementation.address}`);
  return true;
};

func.id = 'GhoAToken';
func.tags = ['GhoAToken', 'full_gho_deploy'];

export default func;
