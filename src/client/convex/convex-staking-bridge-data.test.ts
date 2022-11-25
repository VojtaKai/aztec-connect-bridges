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
} from "../../../typechain-types/index.js";
import { AztecAssetType } from "../bridge-data.js";
import { ConvexBridgeData } from "./convex-staking-bridge-data.js";

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
    id: 1,
    assetType: AztecAssetType.ERC20,
    erc20Address: EthAddress.fromString("0x0000000000000000000000000000000000000010"),
  };

  const representingConvexToken = {
    id: 100,
    assetType: AztecAssetType.ERC20,
    erc20Address: EthAddress.fromString("0x1001001001001001001001001001001001001001"),
  };

  const emptyAsset = {
    id: 0,
    assetType: AztecAssetType.NOT_USED,
    erc20Address: EthAddress.ZERO,
  };

  // Addresses for mocks
  const curveLpToken0 = "0x0000000000000000000000000000000000000001";
  const convexLpToken0 = "0x0000000000000000000000000000000000000002";
  const crvRewards0 = "0x0000000000000000000000000000000000000003";

  const curveLpToken1 = "0x0000000000000000000000000000000000000010";
  const convexLpToken1 = "0x0000000000000000000000000000000000000011";
  const crvRewards1 = "0x0000000000000000000000000000000000000012";

  // Other addresses
  const convexBoosterAddr = "0x5555555555555555555555555555555555555555";

  it("should return correct expected output - staking", async () => {
    const inputValue = 10n;

    // Mocked balances
    const balanceBefore = 0n;

    // Mocks
    boosterMocked = {
      ...boosterMocked,
      poolInfo: jest
        .fn()
        .mockResolvedValueOnce([curveLpToken0, convexLpToken0, "", crvRewards0, "", ""])
        .mockResolvedValueOnce([curveLpToken1, convexLpToken1, "", crvRewards1, "", ""]),
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
      representingConvexToken,
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
      poolInfo: jest
        .fn()
        .mockResolvedValueOnce([curveLpToken0, convexLpToken0, "", crvRewards0, "", ""])
        .mockResolvedValueOnce([curveLpToken1, convexLpToken1, "", crvRewards1, "", ""]),
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

    const expectedOutput = await convexStakingBridge.getExpectedOutput(
      representingConvexToken,
      emptyAsset,
      curveLpToken,
      emptyAsset,
      0n,
      withdrawValue,
    );

    expect(expectedOutput[0]).toBe(10n);
  });

  it("should return correct APR", async () => {
    const totalSupply = BigNumber.from("2362597510871959522728947");
    const rewardRate = BigNumber.from("9695446547950370");

    // Mocks
    boosterMocked = {
      ...boosterMocked,
      poolInfo: jest
        .fn()
        .mockResolvedValueOnce([curveLpToken0, convexLpToken0, "", crvRewards0, "", ""])
        .mockResolvedValueOnce([curveLpToken1, convexLpToken1, "", crvRewards1, "", ""]),
    };

    curveRewardsMocked = {
      ...curveRewardsMocked,
      totalSupply: jest.fn().mockResolvedValueOnce(totalSupply),
      rewardRate: jest.fn().mockResolvedValueOnce(rewardRate),
    };

    IConvexBooster__factory.connect = () => boosterMocked as IConvexBooster;
    ICurveRewards__factory.connect = () => curveRewardsMocked as ICurveRewards;

    // Bridge
    const convexStakingBridge = ConvexBridgeData.create(
      {} as any,
      EthAddress.random(),
      EthAddress.fromString(convexBoosterAddr),
    );

    const expectedAPR = await convexStakingBridge.getAPR(representingConvexToken);

    expect(expectedAPR).toBe(12.941501924435627);
  });

  it("should return correct market size", async () => {
    const totalSupply = BigNumber.from((1e18).toString());

    // Mocks
    boosterMocked = {
      ...boosterMocked,
      poolInfo: jest
        .fn()
        .mockResolvedValueOnce([curveLpToken0, convexLpToken0, "", crvRewards0, "", ""])
        .mockResolvedValueOnce([curveLpToken1, convexLpToken1, "", crvRewards1, "", ""]),
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
      representingConvexToken,
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
      poolInfo: jest
        .fn()
        .mockResolvedValueOnce([curveLpToken0, convexLpToken0, "", crvRewards0, "", ""])
        .mockResolvedValueOnce([curveLpToken1, convexLpToken1, "", crvRewards1, "", ""]),
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

    const expectedOutput = await convexStakingBridge.getUnderlyingAmount(representingConvexToken, withdrawValue);

    expect(expectedOutput).toStrictEqual({
      address: curveLpToken.erc20Address,
      name: underlyingAssetName,
      symbol: underlyingAssetSymbol,
      decimals: underlyingAssetDecimals,
      amount: withdrawValue,
    });
  });
});
