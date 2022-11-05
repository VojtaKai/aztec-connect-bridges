import { EthAddress } from "@aztec/barretenberg/address";
import { BigNumber } from "ethers";
import {
  IERC20Metadata,
  IERC20Metadata__factory,
  IConvexBooster__factory,
  IConvexBooster,
  ICurveLpToken,
  ICurveLpToken__factory,
  ICurveRewards,
  ICurveRewards__factory,
} from "../../../typechain-types";
import { AztecAssetType } from "../bridge-data";
import { ConvexBridgeData } from "./convex-staking-bridge-data";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("convex staking bridge data", () => {
  let boosterMocked: Mockify<IConvexBooster>;
  let curveLpTokenMocked: Mockify<ICurveLpToken>;
  let curveRewardsMocked: Mockify<ICurveRewards>;
  let ERC20Metadata: Mockify<IERC20Metadata>;

  // Tokens
  const curveLpToken = {
    id: 10,
    assetType: AztecAssetType.ERC20,
    erc20Address: EthAddress.fromString("0xe7A3b38c39F97E977723bd1239C3470702568e7B"),
  };

  const virtualAsset = {
    id: 2 ** 29 + 1,
    assetType: AztecAssetType.VIRTUAL,
    erc20Address: EthAddress.ZERO,
  };

  const emptyAsset = {
    id: 0,
    assetType: AztecAssetType.NOT_USED,
    erc20Address: EthAddress.ZERO,
  };

  // Addresses for mocks
  const curveLpToken0 = "0x9fC689CCaDa600B6DF723D9E47D84d76664a1F23";
  const convexToken0 = "0xA1c3492b71938E144ad8bE4c2fB6810b01A43dD8";
  const crvRewards0 = "0x8B55351ea358e5Eda371575B031ee24F462d503e";

  const curveLpToken1 = "0xe7A3b38c39F97E977723bd1239C3470702568e7B";
  const convexToken1 = "0xbE665430e4C439aF6C92ED861939E60A963C6d0c";
  const crvRewards1 = "0x14F02f3b47B407A7a0cdb9292AA077Ce9E124803";

  // Other addresses
  const convexBoosterAddr = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31";

  it("should return correct expected output - staking", async () => {
    const inputValue = 10n;

    // Mocked balances
    const balanceBefore = 0n;

    // Mocks
    boosterMocked = {
      ...boosterMocked,
      poolLength: jest.fn().mockResolvedValue(BigNumber.from(2)),
      poolInfo: jest
        .fn()
        .mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""])
        .mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
      deposit: jest.fn().mockResolvedValue(true),
    };

    curveRewardsMocked = {
      ...curveRewardsMocked,
      balanceOf: jest
        .fn()
        .mockResolvedValueOnce(BigNumber.from(balanceBefore))
        .mockResolvedValueOnce(BigNumber.from(inputValue)),
    };

    IConvexBooster__factory.connect = () => boosterMocked as IConvexBooster;
    ICurveRewards__factory.connect = () => curveRewardsMocked as ICurveRewards;

    // Bridge
    const convexStakingBridge = ConvexBridgeData.create(
      {} as any,
      EthAddress.random(),
      EthAddress.fromString(convexBoosterAddr),
    );

    const expectedOutput = await convexStakingBridge.getExpectedOutput(
      curveLpToken,
      emptyAsset,
      virtualAsset,
      emptyAsset,
      0n,
      inputValue,
    );

    expect(expectedOutput[0]).toBe(10n);
  });

  it("should return correct expected output - withdrawing", async () => {
    const withdrawValue = 10n;

    // Mocked balances
    const balanceBefore = 0n;

    // Mocks
    boosterMocked = {
      ...boosterMocked,
      poolLength: jest.fn().mockResolvedValue(BigNumber.from(2)),
      poolInfo: jest
        .fn()
        .mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""])
        .mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
      withdraw: jest.fn().mockResolvedValue(true),
    };

    curveRewardsMocked = {
      ...curveRewardsMocked,
      withdraw: jest.fn(),
    };

    curveLpTokenMocked = {
      ...curveLpTokenMocked,
      balanceOf: jest
        .fn()
        .mockResolvedValueOnce(BigNumber.from(balanceBefore))
        .mockResolvedValueOnce(BigNumber.from(withdrawValue)),
    };

    IConvexBooster__factory.connect = () => boosterMocked as IConvexBooster;
    ICurveRewards__factory.connect = () => curveRewardsMocked as ICurveRewards;
    ICurveLpToken__factory.connect = () => curveLpTokenMocked as ICurveLpToken;

    // Bridge
    const convexStakingBridge = ConvexBridgeData.create(
      {} as any,
      EthAddress.random(),
      EthAddress.fromString(convexBoosterAddr),
    );

    // Mock an interaction
    convexStakingBridge.interactions = [
      {
        id: virtualAsset.id,
        representingConvexToken: convexToken1,
        valueStaked: withdrawValue,
      },
    ];

    const expectedOutput = await convexStakingBridge.getExpectedOutput(
      virtualAsset,
      emptyAsset,
      curveLpToken,
      emptyAsset,
      0n,
      withdrawValue,
    );

    expect(expectedOutput[0]).toBe(10n);
  });

  it("should throw deposit-withdrawal mismatch error", async () => {
    const withdrawValue = 10n;
    const valueStaked = withdrawValue + 1n;

    // Mocks
    boosterMocked = {
      ...boosterMocked,
      poolLength: jest.fn().mockResolvedValue(BigNumber.from(2)),
      poolInfo: jest
        .fn()
        .mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""])
        .mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
      withdraw: jest.fn().mockResolvedValue(true),
    };

    IConvexBooster__factory.connect = () => boosterMocked as IConvexBooster;

    // Bridge
    const convexStakingBridge = ConvexBridgeData.create(
      {} as any,
      EthAddress.random(),
      EthAddress.fromString(convexBoosterAddr),
    );

    // Mock an interaction, interaction value staked differs from the value one wants to withdraw
    convexStakingBridge.interactions = [
      {
        id: virtualAsset.id,
        representingConvexToken: convexToken1,
        valueStaked: valueStaked,
      },
    ];

    expect(async () => {
      await convexStakingBridge.getExpectedOutput(
        virtualAsset,
        emptyAsset,
        curveLpToken,
        emptyAsset,
        0n,
        withdrawValue,
      );
    }).rejects.toThrowError("Incorrect Interaction Value");
  });

  it("should return correct APR", async () => {
    const totalSupply = BigNumber.from("2362597510871959522728947");
    const rewardRate = BigNumber.from("9695446547950370");

    // Mocks
    boosterMocked = {
      ...boosterMocked,
      poolLength: jest.fn().mockResolvedValue(BigNumber.from(2)),
      poolInfo: jest
        .fn()
        .mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""])
        .mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
    };

    curveRewardsMocked = {
      ...curveRewardsMocked,
      totalSupply: jest.fn().mockResolvedValueOnce(totalSupply),
      rewardRate: jest.fn().mockResolvedValueOnce(rewardRate),
    };

    IConvexBooster__factory.connect = () => boosterMocked as IConvexBooster;
    ICurveRewards__factory.connect = () => curveRewardsMocked as ICurveRewards;

    // Yield Asset
    const convexLpToken = {
      id: 0,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString(convexToken1),
    };

    // Bridge
    const convexStakingBridge = ConvexBridgeData.create(
      {} as any,
      EthAddress.random(),
      EthAddress.fromString(convexBoosterAddr),
    );

    const expectedAPR = await convexStakingBridge.getAPR(convexLpToken);

    expect(expectedAPR).toBe(12.941501924435627);
  });

  it("should return correct market size", async () => {
    const totalSupply = BigNumber.from((1e18).toString());

    // Mocks
    boosterMocked = {
      ...boosterMocked,
      poolLength: jest.fn().mockResolvedValue(BigNumber.from(2)),
      poolInfo: jest
        .fn()
        .mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""])
        .mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
    };

    curveRewardsMocked = {
      ...curveRewardsMocked,
      totalSupply: jest.fn().mockResolvedValueOnce(totalSupply),
    };

    IConvexBooster__factory.connect = () => boosterMocked as IConvexBooster;
    ICurveRewards__factory.connect = () => curveRewardsMocked as ICurveRewards;

    // Bridge
    const convexStakingBridge = ConvexBridgeData.create(
      {} as any,
      EthAddress.random(),
      EthAddress.fromString(convexBoosterAddr),
    );

    // Curve Lp Token is the underlying token
    const expectedMarketSize = await convexStakingBridge.getMarketSize(
      curveLpToken,
      emptyAsset,
      virtualAsset,
      emptyAsset,
      0n,
    );

    expect(expectedMarketSize).toStrictEqual([
      {
        assetId: curveLpToken.id,
        value: totalSupply.toBigInt(),
      },
    ]);
  });

  it("should return correct underlying asset", async () => {
    const withdrawValue = 10n;
    const underlyingAssetName = "underlyingAssetName";
    const underlyingAssetSymbol = "underlyingAssetSymbol";
    const underlyingAssetDecimals = 18;

    // Mocked balances
    const balanceBefore = 0n;

    // Mocks
    boosterMocked = {
      ...boosterMocked,
      poolLength: jest.fn().mockResolvedValue(BigNumber.from(2)),
      poolInfo: jest
        .fn()
        .mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""])
        .mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
      withdraw: jest.fn().mockResolvedValue(true),
    };

    curveRewardsMocked = {
      ...curveRewardsMocked,
      withdraw: jest.fn(),
    };

    curveLpTokenMocked = {
      ...curveLpTokenMocked,
      balanceOf: jest
        .fn()
        .mockResolvedValueOnce(BigNumber.from(balanceBefore))
        .mockResolvedValueOnce(BigNumber.from(withdrawValue)),
    };

    ERC20Metadata = {
      ...ERC20Metadata,
      name: jest.fn().mockResolvedValueOnce(underlyingAssetName),
      symbol: jest.fn().mockResolvedValueOnce(underlyingAssetSymbol),
      decimals: jest.fn().mockResolvedValueOnce(underlyingAssetDecimals),
    };

    IConvexBooster__factory.connect = () => boosterMocked as IConvexBooster;
    ICurveRewards__factory.connect = () => curveRewardsMocked as ICurveRewards;
    ICurveLpToken__factory.connect = () => curveLpTokenMocked as ICurveLpToken;
    IERC20Metadata__factory.connect = () => ERC20Metadata as IERC20Metadata;

    // Bridge
    const convexStakingBridge = ConvexBridgeData.create(
      {} as any,
      EthAddress.random(),
      EthAddress.fromString(convexBoosterAddr),
    );

    // Mock an interaction
    convexStakingBridge.interactions = [
      {
        id: virtualAsset.id,
        representingConvexToken: convexToken1,
        valueStaked: withdrawValue - balanceBefore,
      },
    ];

    const expectedOutput = await convexStakingBridge.getUnderlyingAmount(virtualAsset, withdrawValue);

    expect(expectedOutput).toStrictEqual({
      address: curveLpToken.erc20Address,
      name: underlyingAssetName,
      symbol: underlyingAssetSymbol,
      decimals: underlyingAssetDecimals,
      amount: withdrawValue,
    });
  });

  it("should return present value of an interaction", async () => {
    const inputValue = 10n;

    // Bridge
    const convexStakingBridge = ConvexBridgeData.create(
      {} as any,
      EthAddress.random(),
      EthAddress.fromString(convexBoosterAddr),
    );

    // Mock an interaction
    convexStakingBridge.interactions = [
      {
        id: virtualAsset.id,
        representingConvexToken: convexToken1,
        valueStaked: inputValue,
      },
    ];

    const expectedAssetValue = await convexStakingBridge.getInteractionPresentValue(virtualAsset.id, inputValue);

    expect(expectedAssetValue[0]).toStrictEqual({
      assetId: virtualAsset.id,
      value: inputValue,
    });
  });
});
