// This is a Typescript class designed to help a developer on the frontend use your bridge. You should implement the functions to fetch data from your bridge / L1.

import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers"; // sice s etherem nedelam, ale potrebuju providera
import { BigNumber } from "ethers";
import { createWeb3Provider } from "../aztec/provider"; // asi potrebuju

import "isomorphic-fetch";

import { AssetValue } from "@aztec/barretenberg/asset";
import {
  IERC20Metadata__factory,
  IERC20__factory,
  IRollupProcessor,
  IRollupProcessor__factory,
  IConvexFinanceBooster__factory,
  IConvexFinanceBooster,
  IConvexToken,
  IConvexToken__factory,
  ICurveLpToken,
  ICurveLpToken__factory,
  ICurveRewards,
  ICurveRewards__factory,
  ConvexStakingBridge,
  ConvexStakingBridge__factory,
} from "../../../typechain-types";
import {
  AuxDataConfig,
  AztecAsset,
  AztecAssetType,
  BridgeDataFieldGetters,
  SolidityType,
  UnderlyingAsset,
} from "../bridge-data";

interface IPoolInfo {
  poolPid: number,
  curveLpToken: string,
  convexToken: string,
  curveRewards: string
}
export class ConvexBridgeData implements BridgeDataFieldGetters {
  bridgeAddress = "0x123456789";
  lastPoolLength: Number = 0;
  pools: IPoolInfo[] = [];

  constructor(
    private ethersProvider: Web3Provider,
    private rollupProcessor: IRollupProcessor,
    private convexBooster: IConvexFinanceBooster,
  ) {}

  static create(provider: EthereumProvider, rollupProcessor: EthAddress, convexBooster: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    return new ConvexBridgeData(
      ethersProvider,
      IRollupProcessor__factory.connect(rollupProcessor.toString(), ethersProvider),
      IConvexFinanceBooster__factory.connect(convexBooster.toString(), ethersProvider),
    );
  }

  auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "AuxData determine whether claim (1) or not claim (0) staking rewards at withdrawing",
    },
  ];

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
    inputValue: bigint,
  ): Promise<bigint[]> {
    // input should be again curve Lp token
    // expected number of minted convex tokens. It is denominated in CSB tokens that are minted on the bridge
    // however, they are one to one so I could basicly say, return [inputValue]
    // because other than that I am testing my mocks
    if (inputValue === 0n) {
      throw "InvalidInputAmount"
    }

    // maybe check if assets are supported
    
    if (inputAssetA.assetType != AztecAssetType.ERC20 || 
      outputAssetA.assetType != AztecAssetType.ERC20
  ) {
      throw "invalidAssetType"
  }

    this.loadPools()

    let selectedPool: IPoolInfo | undefined;
    let isDeposit: boolean | undefined;

    for (const pool of this.pools) {
      if (inputAssetA.erc20Address.toString() === pool.curveLpToken) {
        selectedPool = pool
        isDeposit = true
        break
      } else if (outputAssetA.erc20Address.toString() === pool.curveLpToken) {
        selectedPool = pool
        isDeposit = false
        break
      }
    }

    if (selectedPool === undefined) {
      throw "Invalid Assets"
    }

    const curveRewards = ICurveRewards__factory.connect(selectedPool.curveRewards, this.ethersProvider)
    const convexToken = IConvexToken__factory.connect(selectedPool.convexToken, this.ethersProvider)

    if (isDeposit) {
      const balanceBefore = (await convexToken.balanceOf(curveRewards.address)).toBigInt()
      await this.convexBooster.deposit(selectedPool.poolPid, inputValue, true)
      const balanceAfter = (await convexToken.balanceOf(curveRewards.address)).toBigInt()

      return [balanceAfter - balanceBefore]
    } else {
      const claimRewards = auxData === 1
      await curveRewards.withdraw(inputValue, claimRewards)
      await this.convexBooster.withdraw(selectedPool.poolPid, inputValue)
      return [inputValue]
    }
  }

  // @param yieldAsset in this case yieldAsset are yv tokens (e.g. yvDai, yvEth, etc.)
  // async getAPR(yieldAsset: AztecAsset): Promise<number> {
  //   type TminVaultStruct = {
  //     address: string;
  //     apy: {
  //       gross_apr: number;
  //     };
  //   };
  //   const allVaults = (await (
  //     await fetch("https://api.yearn.finance/v1/chains/1/vaults/all")
  //   ).json()) as TminVaultStruct[];
  //   const currentVault = allVaults.find((vault: TminVaultStruct) =>
  //     EthAddress.fromString(vault.address).equals(yieldAsset.erc20Address),
  //   );
  //   if (currentVault) {
  //     const grossAPR = currentVault.apy.gross_apr;
  //     return grossAPR * 100;
  //   }
  //   return 0;
  // }

  async getAPR(yieldAsset: AztecAsset): Promise<number> {
    // Not taking into account how the deposited funds will change the yield
    // The approximate number of blocks per year that is assumed by the interest rate model

    // yieldAsset is going to be curve Rewards
    const blocksPerYear = 7132 * 365;
    const curveRewards = ICurveRewards__factory.connect(yieldAsset.erc20Address.toString(), this.ethersProvider);
    
    const totalSupply = await curveRewards.totalSupply();
    const rewardRatePerBlock = await curveRewards.rewardRate();
    // return Number((((totalSupply.add((rewardRatePerBlock.mul(blocksPerYear)))).div(totalSupply)).sub(1)).mul(10 ** 2));
    return Number(rewardRatePerBlock.mul(blocksPerYear).div(totalSupply).mul(10 ** 2));
  }

  // I do actually thing this is better
  async getMarketSizeEasier(
    curveLpTokens: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
  ): Promise<AssetValue[]> {
    // input curveLpTokens
    // output are CSB tokens

    // load pools if needed
    this.loadPools()

    const selectedPool = this.pools.find(pool => pool.curveLpToken === curveLpTokens.erc20Address.toString())
    if (!selectedPool) {
      return []
    }
    const curveRewards = ICurveRewards__factory.connect(selectedPool.curveRewards, this.ethersProvider)
    const tokenSupply = await curveRewards.totalSupply()
    return [{ assetId: curveLpTokens.id, value: tokenSupply.toBigInt()}]
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
  ): Promise<AssetValue[]> {
    // const yvTokenContract = IYearnVault__factory.connect(yvToken.erc20Address.toString(), this.ethersProvider);
    // const totalAssets = await yvTokenContract.totalAssets();
    // return [{ assetId: underlying.id, value: totalAssets.toBigInt() }];

    // input should be curveLpToken and the market size should be denominated in it
    // output is CSB token after all and it is minted for any pool, so the number doesn't really show how strong a pool is

    this.loadPools()    

    let selectedPool: IPoolInfo | undefined;
    let correctAsset: AztecAsset | undefined;

    for (const pool of this.pools) {
      if (inputAssetA.erc20Address.toString() === pool.curveLpToken) {
        selectedPool = pool
        correctAsset = inputAssetA
        break
      } else if (outputAssetA.erc20Address.toString() === pool.curveLpToken) {
        selectedPool = pool
        correctAsset = outputAssetA
        break
      }
    }

    if (!selectedPool || !correctAsset) {
      throw new Error("Invalid Assets")
    }

    const curveRewards = ICurveRewards__factory.connect(selectedPool.curveRewards, this.ethersProvider)
    const tokenSupply = await curveRewards.totalSupply()
    return [{ assetId: correctAsset.id, value: tokenSupply.toBigInt()}]

    // go over all pools
    // find selectedPool
    // check totalSupply of the crvRewards contract -> to nam rekne, kolik lidi ten druh Curve LP Tokenu taky investovalo do toho Convex Poolu
    // assetId by mel byt ten vstupni token!!! Pro totalSupply ale koukam na to, kolik je staknutejch tech vystupnich, jelikoz jsou 1:1
    // AssetId je teda id of inputAssetA
  }

  async getUnderlyingAmount(csbAsset: AztecAsset, amount: bigint): Promise<UnderlyingAsset> {
    // csb token
    // definuje curveLpToken = underlying asset
    // jakej pool to matchne
    // selectedPool.curveLpToken
    // interface curveLpToken bude potrebovat name, symbol, decimals, address, mnozstvi zpet pri withdrawalu
    // ziskej zpet curve lp token
    const emptyAsset: AztecAsset = {
      id: 0,
      erc20Address: EthAddress.ZERO,
      assetType: AztecAssetType.NOT_USED,
    };

    // go pool by pool, get curve lp token address and place it under underlying asset erc20 address
    // while it keeps failing, keep going pool by pool
    // eventually find the correct one and perform withdrawal!

    // curve lp token
    const underlyingAsset: AztecAsset = {
      id: 0,
      erc20Address: EthAddress.fromString('0x123456789'),
      assetType: AztecAssetType.ERC20,
    };

    // should withdraw, if 
    const underlyingAssetAmount = await this.getExpectedOutput(csbAsset, emptyAsset, underlyingAsset, emptyAsset, 0, amount)

    const curveLpToken = IERC20Metadata__factory.connect(underlyingAsset.erc20Address.toString(), this.ethersProvider)

    return {
      address: underlyingAsset.erc20Address,
      name: await curveLpToken.name(),
      symbol: await curveLpToken.symbol(),
      decimals: await curveLpToken.decimals(),
      amount: underlyingAssetAmount[0]
    }
  }

  private async isSupportedAsset(asset: AztecAsset): Promise<boolean> {
    if (asset.assetType == AztecAssetType.ETH) return true;

    const assetAddress = EthAddress.fromString(await this.rollupProcessor.getSupportedAsset(asset.id));
    return assetAddress.equals(asset.erc20Address);
  }

  private async loadPools() {
    const currentPoolLength = Number(await this.convexBooster.poolLength());
      if (currentPoolLength !== this.lastPoolLength) {
        let i = 0;
        while (i < currentPoolLength) {
          const poolInfo = await this.convexBooster.poolInfo(i);
          this.pools.push({
            poolPid: i,
            curveLpToken: poolInfo[0],
            convexToken: poolInfo[1],
            curveRewards: poolInfo[3]
          })
          i++
        }
      }
      this.lastPoolLength = currentPoolLength
  }
}
