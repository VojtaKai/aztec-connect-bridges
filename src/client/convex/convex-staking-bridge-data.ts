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

  // I am not able to distinguish aux data just from the assets
  // Aux data are utilized to claim rewards of the staked tokens (or not)
  // async getAuxData(
  //   inputAssetA: AztecAsset,
  //   inputAssetB: AztecAsset,
  //   outputAssetA: AztecAsset,
  //   outputAssetB: AztecAsset,
  // ): Promise<number[]> {

  //   // upon withdrawal
  //   // after crvRewards.withdraw()
  //   // check convexToken balance for bridge
  //   // if rewards activated it should be more than the inital input amount
  //   return [10] // wrong...
  // }

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
    inputValue: bigint,
  ): Promise<bigint[]> {
    // mam input asset a mam output asset
    // chci vratit, co bridge normalne vraci, coz je CSB token v urcite kvantite - outputValueA
    // mam i auxData, ta ale hrajou malou roli a ted je muzu ignorovat

    if (inputValue === 0n) {
      throw "InvalidInputAmount"
    }
    
    // zkontroluj si, ze assety maji spravny type
    if (inputAssetA.assetType != AztecAssetType.ERC20 || 
      outputAssetA.assetType != AztecAssetType.ERC20
  ) {
      throw "invalidAssetType"
  }
    // mam pooly - ty potrebuju, abych tam nasel assets a urcil spravny pool
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

    // depositni nebo withdrawni
    if (isDeposit) {
      //deposit and check balance
      const balanceBefore = (await convexToken.balanceOf(curveRewards.address)).toBigInt()
      await this.convexBooster.deposit(selectedPool.poolPid, inputValue, true)
      const balanceAfter = (await convexToken.balanceOf(curveRewards.address)).toBigInt()

      return [balanceAfter - balanceBefore] // or just inputValue
    } else {
      // withdraw and check balance
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

  async getMarketSizeEasier(
    curveLpTokens: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
  ): Promise<AssetValue[]> {
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

  async getUnderlyingAmount(vaultAsset: AztecAsset, amount: bigint): Promise<UnderlyingAsset> {
    const emptyAsset: AztecAsset = {
      id: 0,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
    const vaultContract = IYearnVault__factory.connect(vaultAsset.erc20Address.toString(), this.ethersProvider);
    const underlyingAsset: AztecAsset = {
      id: 0,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString(await vaultContract.token()),
    };
    const tokenContract = IERC20Metadata__factory.connect(underlyingAsset.erc20Address.toString(), this.ethersProvider);
    const namePromise = tokenContract.name();
    const symbolPromise = tokenContract.symbol();
    const decimalsPromise = tokenContract.decimals();
    const amountPromise = this.getExpectedOutput(vaultAsset, emptyAsset, underlyingAsset, emptyAsset, 1, amount);
    return {
      address: underlyingAsset.erc20Address,
      name: await namePromise,
      symbol: await symbolPromise,
      decimals: await decimalsPromise,
      amount: (await amountPromise)[0],
    };
  }

  private async isSupportedAsset(asset: AztecAsset): Promise<boolean> {
    if (asset.assetType == AztecAssetType.ETH) return true;

    const assetAddress = EthAddress.fromString(await this.rollupProcessor.getSupportedAsset(asset.id));
    return assetAddress.equals(asset.erc20Address);
  }

  private async getAllVaultsAndTokens(): Promise<[EthAddress[], { [key: string]: EthAddress[] }]> {
    const allYvETH: EthAddress[] = this.allYvETH || [];
    const allVaultsForTokens: { [key: string]: EthAddress[] } = this.allVaultsForTokens || {};

    if (!this.allVaultsForTokens) {
      const numTokens = await this.yRegistry.numTokens();
      for (let index = 0; index < Number(numTokens); index++) {
        const token = await this.yRegistry.tokens(index);
        const vault = await this.yRegistry.latestVault(token);
        if (!allVaultsForTokens[token]) {
          allVaultsForTokens[token] = [];
        }
        allVaultsForTokens[token].push(EthAddress.fromString(vault));
        if (token === this.wETH) {
          allYvETH.push(EthAddress.fromString(vault));
        }
      }
      this.allYvETH = allYvETH;
    }
    return [allYvETH, allVaultsForTokens];
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
