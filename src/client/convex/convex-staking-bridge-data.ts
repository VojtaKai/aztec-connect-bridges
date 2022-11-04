import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import { createWeb3Provider } from "../aztec/provider";

import "isomorphic-fetch";

import { AssetValue } from "@aztec/barretenberg/asset";
import {
  IERC20Metadata__factory,
  IRollupProcessor,
  IRollupProcessor__factory,
  IConvexBooster__factory,
  IConvexBooster,
  ICurveLpToken,
  ICurveLpToken__factory,
  ICurveRewards,
  ICurveRewards__factory
} from "../../../typechain-types";
import {
  AuxDataConfig,
  AztecAsset,
  AztecAssetType,
  BridgeDataFieldGetters,
  SolidityType,
  UnderlyingAsset,
} from "../bridge-data";
import { BigNumber } from "ethers";


export interface IPoolInfo {
  poolPid: number,
  curveLpToken: string,
  convexToken: string,
  curveRewards: string
}

interface IBridgeInteraction {
  id: number,
  representingConvexToken: string,
  valueStaked: bigint
}

export class ConvexBridgeData implements BridgeDataFieldGetters {
  bridgeAddress = "0x123456789";
  lastPoolLength: number = 0;
  pools: IPoolInfo[] = [];
  interactions: IBridgeInteraction[] = [];

  constructor(
    private ethersProvider: Web3Provider,
    private rollupProcessor: IRollupProcessor,
    private booster: IConvexBooster,
  ) {}

  static create(provider: EthereumProvider, rollupProcessor: EthAddress, booster: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    return new ConvexBridgeData(
      ethersProvider,
      IRollupProcessor__factory.connect(rollupProcessor.toString(), ethersProvider),
      IConvexBooster__factory.connect(booster.toString(), ethersProvider),
    );
  }

  auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "AuxData determine whether claim (1) or not claim (anything but 1) staking rewards at withdrawing",
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
    if (inputValue === 0n) {
      throw "InvalidInputAmount"
    }

    await this.loadPools()

    let selectedPool: IPoolInfo | undefined;
    let curveRewards: ICurveRewards
    let curveLpToken: ICurveLpToken

    if (inputAssetA.assetType == AztecAssetType.ERC20 && outputAssetA.assetType == AztecAssetType.VIRTUAL) {
      selectedPool = this.pools.find(p => p.curveLpToken === inputAssetA.erc20Address.toString())
      if (!selectedPool) {
        throw new Error("Invalid Input A")
      }

      curveRewards = ICurveRewards__factory.connect(selectedPool.curveRewards, this.ethersProvider)


      const balanceBefore = (await curveRewards.balanceOf(this.bridgeAddress)).toBigInt()
      await this.booster.deposit(selectedPool.poolPid, inputValue, true)
      const balanceAfter = (await curveRewards.balanceOf(this.bridgeAddress)).toBigInt()

      this.interactions.push({
        id: outputAssetA.id,
        representingConvexToken: selectedPool.convexToken,
        valueStaked: inputValue
      })

      return [balanceAfter - balanceBefore]
    } else if (inputAssetA.assetType == AztecAssetType.VIRTUAL && outputAssetA.assetType == AztecAssetType.ERC20) {
      const interaction = this.interactions.find(i => i.id === inputAssetA.id)
      if (!interaction) {
        throw new Error("Unknown Virtual Asset")
      }

      if (interaction.valueStaked !== inputValue) {
        throw new Error("Incorrect Interaction Value")
      }

      selectedPool = this.pools.find(p => p.curveLpToken === outputAssetA.erc20Address.toString())

      if (!selectedPool || selectedPool.convexToken != interaction.representingConvexToken) {
        throw new Error("Invalid Output Token")
      }

      curveRewards = ICurveRewards__factory.connect(selectedPool.curveRewards, this.ethersProvider)
      curveLpToken = ICurveLpToken__factory.connect(outputAssetA.erc20Address.toString(), this.ethersProvider)

      const claimRewards = auxData === 1

      const balanceBefore = (await curveLpToken.balanceOf(this.bridgeAddress)).toBigInt()

      await curveRewards.withdraw(inputValue, claimRewards)
      await this.booster.withdraw(selectedPool.poolPid, inputValue)

      const balanceAfter = (await curveLpToken.balanceOf(this.bridgeAddress)).toBigInt()

      return [balanceAfter - balanceBefore]

    } else {
      throw new Error("Invalid Asset Type")
    }
  }

  async getAPR(yieldAsset: AztecAsset): Promise<number> {
    // yieldAsset is the Convex LP token
    // Not taking into account how the deposited funds will change the yield
    await this.loadPools()

    const curveRewardsAddress = this.pools.find(p => p.convexToken === yieldAsset.erc20Address.toString())?.curveRewards

    if (!curveRewardsAddress) {
      throw new Error("Invalid yield asset")
    }

    const secondsInYear = 3600 * 24 * 365;
    const curveRewards = ICurveRewards__factory.connect(curveRewardsAddress, this.ethersProvider);
    
    const totalSupply = Number(await curveRewards.totalSupply());
    const rewardRatePerSecond = Number(await curveRewards.rewardRate());

    return rewardRatePerSecond * secondsInYear / totalSupply * (10 ** 2)
  }

  async getMarketSize(
    underlyingToken: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
    ): Promise<AssetValue[]> {
    // underlying token is the Curve LP token

    await this.loadPools()

    const selectedPool = this.pools.find(pool => pool.curveLpToken === underlyingToken.erc20Address.toString())

    if (!selectedPool) {
      throw new Error("Invalid Input A")
    }

    const curveRewards = ICurveRewards__factory.connect(selectedPool.curveRewards, this.ethersProvider)
    const tokenSupply = await curveRewards.totalSupply()
    return [{ assetId: underlyingToken.id, value: tokenSupply.toBigInt()}]
  }

  async getUnderlyingAmount(virtualAsset: AztecAsset, amount: bigint): Promise<UnderlyingAsset> {
    await this.loadPools()

    const emptyAsset: AztecAsset = {
      id: 0,
      erc20Address: EthAddress.ZERO,
      assetType: AztecAssetType.NOT_USED,
    };


    const representingConvexToken = this.interactions.find(i => i.id === virtualAsset.id)?.representingConvexToken

    if (!representingConvexToken) {
      throw new Error('Unknown Virtual Asset')
    }


    const selectedPool = this.pools.find(pool => pool.convexToken === representingConvexToken)

    if (selectedPool == undefined) {
      throw new Error("Pool not found")
    }

    // curve lp token
    const underlyingAsset: AztecAsset = {
      id: 0,
      erc20Address: EthAddress.fromString(selectedPool.curveLpToken),
      assetType: AztecAssetType.ERC20,
    };

    // withdraw
    const underlyingAssetAmount = await this.getExpectedOutput(virtualAsset, emptyAsset, underlyingAsset, emptyAsset, 0, amount)

    const curveLpToken = IERC20Metadata__factory.connect(underlyingAsset.erc20Address.toString(), this.ethersProvider)

    return {
      address: underlyingAsset.erc20Address,
      name: await curveLpToken.name(),
      symbol: await curveLpToken.symbol(),
      decimals: await curveLpToken.decimals(),
      amount: underlyingAssetAmount[0]
    }
  }

  async getInteractionPresentValue(interactionNonce: number, inputValue: bigint): Promise<AssetValue[]> {
    const interaction = this.interactions.find(i => i.id === interactionNonce)
    if (!interaction) {
      throw new Error("Unknown interaction nonce")
    }
    // input convex tokens are minted in 1:1 ratio to staked curve lp tokens, input = output
    return [{
      assetId: interaction.id,
      value: interaction.valueStaked
    }]
  }

  private async loadPools() {
    const currentPoolLength = (await this.booster.poolLength()).toNumber();
      if (currentPoolLength !== this.lastPoolLength) {
        let i = this.lastPoolLength;
        while (i < currentPoolLength) {
          const poolInfo = await this.booster.poolInfo(BigNumber.from(i));
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
