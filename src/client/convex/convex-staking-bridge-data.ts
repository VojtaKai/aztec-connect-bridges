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
  ICurveRewards__factory,
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
  poolId: number;
  convexToken: string;
  curveRewards: string;
}

export class ConvexBridgeData implements BridgeDataFieldGetters {
  bridgeAddress = "0x123456789";
  pools = new Map<string, IPoolInfo>();
  deployedClones = new Map<string, string>();

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
    auxData: bigint,
    inputValue: bigint,
  ): Promise<bigint[]> {
    // Set pools, deploy representing Convex token and clone for each
    if (this.pools.size === 0) {
      await this.loadPool(32);
      await this.loadPool(1);
    }

    if (inputAssetA.assetType != AztecAssetType.ERC20 || outputAssetA.assetType != AztecAssetType.ERC20) {
      throw new Error("Invalid Asset Type");
    }

    // if oba undefined
    if (
      this.deployedClones.has(inputAssetA.erc20Address.toString()) &&
      this.deployedClones.has(outputAssetA.erc20Address.toString())
    ) {
      throw new Error("Unknown Asset A");
    }

    let selectedPool: IPoolInfo | undefined;
    let curveRewards: ICurveRewards;
    let curveLpToken: ICurveLpToken;

    // deposit
    if (this.deployedClones.get(inputAssetA.erc20Address.toString()) === outputAssetA.erc20Address.toString()) {
      selectedPool = this.pools.get(inputAssetA.erc20Address.toString());

      if (!selectedPool) {
        throw new Error("Invalid Input A");
      }

      curveRewards = ICurveRewards__factory.connect(selectedPool.curveRewards, this.ethersProvider);

      const balanceBefore = (await curveRewards.balanceOf(this.bridgeAddress)).toBigInt();
      await this.booster.deposit(selectedPool.poolId, inputValue, true);
      const balanceAfter = (await curveRewards.balanceOf(this.bridgeAddress)).toBigInt();

      return [balanceAfter - balanceBefore];
    } else if (this.deployedClones.get(outputAssetA.erc20Address.toString()) === inputAssetA.erc20Address.toString()) {
      selectedPool = this.pools.get(outputAssetA.erc20Address.toString());

      if (!selectedPool) {
        throw new Error("Invalid Output A");
      }

      curveRewards = ICurveRewards__factory.connect(selectedPool.curveRewards, this.ethersProvider);
      curveLpToken = ICurveLpToken__factory.connect(outputAssetA.erc20Address.toString(), this.ethersProvider);

      const balanceBefore = (await curveLpToken.balanceOf(this.bridgeAddress)).toBigInt();

      await curveRewards.withdraw(inputValue, true);
      await this.booster.withdraw(selectedPool.poolId, inputValue);

      const balanceAfter = (await curveLpToken.balanceOf(this.bridgeAddress)).toBigInt();

      return [balanceAfter - balanceBefore];
    } else {
      throw new Error("Invalid Output A");
    }
  }

  async getAPR(yieldAsset: AztecAsset): Promise<number> {
    // yieldAsset is the Representing Convex token (RCT)
    // Not taking into account how the deposited funds will change the yield
    // Set pools, deploy representing Convex token and clone for each
    if (this.pools.size === 0) {
      await this.loadPool(32);
      await this.loadPool(1);
    }

    const curveLpToken = (
      Array.from(this.deployedClones)?.find(token => token[1] === yieldAsset.erc20Address.toString()) as [
        string,
        string,
      ]
    )[0];

    const curveRewardsAddress = this.pools.get(curveLpToken)?.curveRewards;

    if (!curveRewardsAddress) {
      throw new Error("Invalid yield asset");
    }

    const secondsInYear = 3600 * 24 * 365;
    const curveRewards = ICurveRewards__factory.connect(curveRewardsAddress, this.ethersProvider);

    const totalSupply = Number(await curveRewards.totalSupply());
    const rewardRatePerSecond = Number(await curveRewards.rewardRate());

    return ((rewardRatePerSecond * secondsInYear) / totalSupply) * 10 ** 2;
  }

  async getMarketSize(
    underlyingToken: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
  ): Promise<AssetValue[]> {
    // underlying token is the Curve LP token

    // Set pools, deploy representing Convex token and clone for each
    if (this.pools.size === 0) {
      await this.loadPool(32);
      await this.loadPool(1);
    }

    const selectedPool = this.pools.get(underlyingToken.erc20Address.toString());

    if (!selectedPool) {
      throw new Error("Invalid Input A");
    }

    const curveRewards = ICurveRewards__factory.connect(selectedPool.curveRewards, this.ethersProvider);
    const tokenSupply = await curveRewards.totalSupply();
    return [{ assetId: underlyingToken.id, value: tokenSupply.toBigInt() }];
  }

  async getUnderlyingAmount(representingConvexAsset: AztecAsset, amount: bigint): Promise<UnderlyingAsset> {
    // Set pools, deploy representing Convex token and clone for each
    if (this.pools.size === 0) {
      await this.loadPool(32);
      await this.loadPool(1);
    }

    const emptyAsset: AztecAsset = {
      id: 0,
      erc20Address: EthAddress.ZERO,
      assetType: AztecAssetType.NOT_USED,
    };

    const curveLpTokenAddr = (
      Array.from(this.deployedClones)?.find(token => token[1] === representingConvexAsset.erc20Address.toString()) as [
        string,
        string,
      ]
    )[0];

    // curve lp token
    const underlyingAsset: AztecAsset = {
      id: 1,
      erc20Address: EthAddress.fromString(curveLpTokenAddr),
      assetType: AztecAssetType.ERC20,
    };

    // withdraw
    const underlyingAssetAmount = await this.getExpectedOutput(
      representingConvexAsset,
      emptyAsset,
      underlyingAsset,
      emptyAsset,
      0n,
      amount,
    );

    const curveLpToken = IERC20Metadata__factory.connect(underlyingAsset.erc20Address.toString(), this.ethersProvider);

    return {
      address: underlyingAsset.erc20Address,
      name: await curveLpToken.name(),
      symbol: await curveLpToken.symbol(),
      decimals: await curveLpToken.decimals(),
      amount: underlyingAssetAmount[0],
    };
  }

  private async loadPool(poolId: number) {
    const poolInfo = await this.booster.poolInfo(BigNumber.from(poolId));
    this.pools.set(poolInfo[0], {
      poolId: poolId,
      convexToken: poolInfo[1],
      curveRewards: poolInfo[3],
    });
    this.deployedClones.set(poolInfo[0], `0x100000000000000000000000000000000000000${poolId}`);
  }
}
