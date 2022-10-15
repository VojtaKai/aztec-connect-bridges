// This is a Typescript class designed to help a developer on the frontend use your bridge. You should implement the functions to fetch data from your bridge / L1.
// to do

// getMarketSize
// priprav si curveLpToken jako input, CSB jako output
// mockni tu fci, kterou dostavam pooly
// mockni total supply pro konkretni pool

// priprav si assety

// 1. input blbe, throw error
// 2. output blbe, throw error
// 3. input value 0, throw error,
// 4. oba spravne, ale nenajde pool, throw error
// 5. oba spravne, proved deposit
// 6. oba spravne, proved withdrawal
// 7. oba spravne, proved withdrawal s claim


// auxData
// dalo by se - oba assety, udelej withdraw jednou s claimem podruhy bez, kdyz to vrati vetsi hodnotu nez inputValue, tak [1] claimed, jinak [0]


// ARP
// ((totalSupply + (rewardRate * blocks_per_year))/total_supply - 1) * 100  

import { EthAddress } from "@aztec/barretenberg/address";
import { BigNumber } from "ethers";
import {
    IERC20Metadata,
    IERC20Metadata__factory,
    IERC20__factory,
    IRollupProcessor,
    IRollupProcessor__factory,
    IConvexDeposit__factory,
    IConvexDeposit,
    IConvexToken,
    IConvexToken__factory,
    ICurveLpToken,
    ICurveLpToken__factory,
    ICurveRewards,
    ICurveRewards__factory,
} from "../../../typechain-types";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { ConvexBridgeData, IPoolInfo } from "./convex-staking-bridge-data";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("convex staking bridge data", () => {
  let convexDeposit: Mockify<IConvexDeposit>;
  let convexTokenClass: Mockify<IConvexToken>;
  let curveLpTokenClass: Mockify<ICurveLpToken>;
  let curveRewardsClass: Mockify<ICurveRewards>;
  let curveLpTokenERC20: Mockify<IERC20Metadata>;
  let rollupProcessorContract: Mockify<IRollupProcessor>;
  // let cerc20Contract: Mockify<ICERC20>;
  // let erc20Contract: Mockify<IERC20>;

  const instanceNonce = 10 ** 29 + 1;

//   let ethAsset: AztecAsset;
//   let cethAsset: AztecAsset;
//   let daiAsset: AztecAsset;
//   let cdaiAsset: AztecAsset;
//   let emptyAsset: AztecAsset;

    // let curveLpToken: AztecAsset
    // let virtualAsset: AztecAsset
    // let emptyAsset: AztecAsset

    const curveLpToken = {
      id: 10,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0xe7A3b38c39F97E977723bd1239C3470702568e7B")
    }

    const virtualAsset = {
      id: instanceNonce,
      assetType: AztecAssetType.VIRTUAL,
      erc20Address: EthAddress.ZERO,
    };

    const emptyAsset = {
      id: 0,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };

  beforeAll(() => {})
  beforeEach(() => {})

  it("should return correct expected output - staking", async () => {
    const inputValue = 10n
    // addresses
    const convexDepositAddr = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"

    const curveLpToken0 = "0x9fC689CCaDa600B6DF723D9E47D84d76664a1F23"
    const convexToken0 = "0xA1c3492b71938E144ad8bE4c2fB6810b01A43dD8"
    const crvRewards0 = "0x8B55351ea358e5Eda371575B031ee24F462d503e"

    const curveLpToken1 = "0xe7A3b38c39F97E977723bd1239C3470702568e7B"
    const convexToken1 = "0xbE665430e4C439aF6C92ED861939E60A963C6d0c"
    const crvRewards1 = "0x14F02f3b47B407A7a0cdb9292AA077Ce9E124803"

    // mocked balances
    const balanceBefore = 0n

    // Mocks
    convexDeposit = {
      ...convexDeposit,
      poolLength: jest.fn().mockResolvedValue(2),
      poolInfo: jest.fn().mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""]).mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
      deposit: jest.fn().mockResolvedValue(true)
    }

    convexTokenClass = {
      ...convexTokenClass,
      balanceOf: jest.fn().mockResolvedValueOnce(BigNumber.from(balanceBefore)).mockResolvedValueOnce(BigNumber.from(inputValue))
    }

    IConvexDeposit__factory.connect = () => convexDeposit as any
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any
    IConvexToken__factory.connect = () => convexTokenClass as any
    
    const convexStakingBridge = ConvexBridgeData.create({} as any, EthAddress.random(), EthAddress.fromString(convexDepositAddr))

    const expectedOutput = await convexStakingBridge.getExpectedOutput(curveLpToken, emptyAsset, virtualAsset, emptyAsset, 0, inputValue)

    expect(expectedOutput[0]).toBe(10n)

  })

  it("should return correct expected output - withdrawing", async () => {
    const withdrawValue = 10n
    // addresses
    const convexDepositAddr = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"

    const curveLpToken0 = "0x9fC689CCaDa600B6DF723D9E47D84d76664a1F23"
    const convexToken0 = "0xA1c3492b71938E144ad8bE4c2fB6810b01A43dD8"
    const crvRewards0 = "0x8B55351ea358e5Eda371575B031ee24F462d503e"

    const curveLpToken1 = "0xe7A3b38c39F97E977723bd1239C3470702568e7B"
    const convexToken1 = "0xbE665430e4C439aF6C92ED861939E60A963C6d0c"
    const crvRewards1 = "0x14F02f3b47B407A7a0cdb9292AA077Ce9E124803"

    // mocked balances
    const balanceBefore = 0n

    // Mocks
    convexDeposit = {
      ...convexDeposit,
      poolLength: jest.fn().mockResolvedValue(2),
      poolInfo: jest.fn().mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""]).mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
      withdraw: jest.fn().mockResolvedValue(true)
    }

    curveRewardsClass = {
      ...curveRewardsClass,
      withdraw: jest.fn()
    }

    curveLpTokenClass = {
      ...curveLpTokenClass,
      balanceOf: jest.fn().mockResolvedValueOnce(BigNumber.from(balanceBefore)).mockResolvedValueOnce(BigNumber.from(withdrawValue))
    }

    IConvexDeposit__factory.connect = () => convexDeposit as any
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any;
    IConvexToken__factory.connect = () => convexTokenClass as any
    ICurveRewards__factory.connect = () => curveRewardsClass as any
    ICurveLpToken__factory.connect = () => curveLpTokenClass as any
    
    const convexStakingBridge = ConvexBridgeData.create({} as any, EthAddress.random(), EthAddress.fromString(convexDepositAddr))

    // mock an interaction
    convexStakingBridge.interactions = [{
      id: virtualAsset.id,
      representedConvexToken: convexToken1
    }]

    // convexStakingBridge.interactions as any = jest.mock()

    const expectedOutput = await convexStakingBridge.getExpectedOutput(virtualAsset, emptyAsset, curveLpToken, emptyAsset, 0, withdrawValue)

    expect(expectedOutput[0]).toBe(10n)

  })

  it("should return correct APR", async () => {
    // const totalSupply = BigNumber.from(1)
    // const rewardRate = BigNumber.from(1)
    // const totalSupply = BigNumber.from("5597662403267968932399")
    // const rewardRate = BigNumber.from("205640903941133")
    const totalSupply = BigNumber.from("2362597510871959522728947")
    const rewardRate = BigNumber.from("9695446547950370")
    // addresses
    const convexDepositAddr = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"

    const curveLpToken0 = "0x9fC689CCaDa600B6DF723D9E47D84d76664a1F23"
    const convexToken0 = "0xA1c3492b71938E144ad8bE4c2fB6810b01A43dD8"
    const crvRewards0 = "0x8B55351ea358e5Eda371575B031ee24F462d503e"

    const curveLpToken1 = "0xe7A3b38c39F97E977723bd1239C3470702568e7B"
    const convexToken1 = "0xbE665430e4C439aF6C92ED861939E60A963C6d0c"
    const crvRewards1 = "0x14F02f3b47B407A7a0cdb9292AA077Ce9E124803"

    // Mocks
    convexDeposit = {
      ...convexDeposit,
      poolLength: jest.fn().mockResolvedValue(2),
      poolInfo: jest.fn().mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""]).mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
    }

    curveRewardsClass = {
      ...curveRewardsClass,
      totalSupply: jest.fn().mockResolvedValueOnce(totalSupply),
      rewardRate: jest.fn().mockResolvedValueOnce(rewardRate)
    }

    IConvexDeposit__factory.connect = () => convexDeposit as any
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any
    ICurveRewards__factory.connect = () => curveRewardsClass as any

    const convexStakingBridge = ConvexBridgeData.create({} as any, EthAddress.random(), EthAddress.fromString(convexDepositAddr))

    const convexToken = {
      id: 0,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString(convexToken1)
    }

    const expectedAPR = await convexStakingBridge.getAPR(convexToken)

    expect(expectedAPR).toBe(1.068273052373552)

  })

  it("should return correct market size", async () => {
    const totalSupply = BigNumber.from(1)

    // addresses
    const convexDepositAddr = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"

    const curveLpToken0 = "0x9fC689CCaDa600B6DF723D9E47D84d76664a1F23"
    const convexToken0 = "0xA1c3492b71938E144ad8bE4c2fB6810b01A43dD8"
    const crvRewards0 = "0x8B55351ea358e5Eda371575B031ee24F462d503e"

    const curveLpToken1 = "0xe7A3b38c39F97E977723bd1239C3470702568e7B"
    const convexToken1 = "0xbE665430e4C439aF6C92ED861939E60A963C6d0c"
    const crvRewards1 = "0x14F02f3b47B407A7a0cdb9292AA077Ce9E124803"

    // Mocks
    convexDeposit = {
      ...convexDeposit,
      poolLength: jest.fn().mockResolvedValue(2),
      poolInfo: jest.fn().mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""]).mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
    }

    curveRewardsClass = {
      ...curveRewardsClass,
      totalSupply: jest.fn().mockResolvedValueOnce(totalSupply),
    }

    IConvexDeposit__factory.connect = () => convexDeposit as any
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any
    ICurveRewards__factory.connect = () => curveRewardsClass as any
    
    const convexStakingBridge = ConvexBridgeData.create({} as any, EthAddress.random(), EthAddress.fromString(convexDepositAddr))

    const expectedMarketSize = await convexStakingBridge.getMarketSize(curveLpToken, emptyAsset, virtualAsset, emptyAsset, 0)

    expect(expectedMarketSize).toStrictEqual([{
      assetId: curveLpToken.id,
      value: totalSupply.toBigInt()
    }])

  })

  it("should return correct underlying asset", async () => {
    const withdrawValue = 10n
    const underlyingAssetName = 'underlyingAssetName'
    const underlyingAssetSymbol = 'underlyingAssetSymbol'
    const underlyingAssetDecimals = 18
    // addresses
    const convexDepositAddr = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"

    const curveLpToken0 = "0x9fC689CCaDa600B6DF723D9E47D84d76664a1F23"
    const convexToken0 = "0xA1c3492b71938E144ad8bE4c2fB6810b01A43dD8"
    const crvRewards0 = "0x8B55351ea358e5Eda371575B031ee24F462d503e"

    const curveLpToken1 = "0xe7A3b38c39F97E977723bd1239C3470702568e7B"
    const convexToken1 = "0xbE665430e4C439aF6C92ED861939E60A963C6d0c"
    const crvRewards1 = "0x14F02f3b47B407A7a0cdb9292AA077Ce9E124803"

    // mocked balances
    const balanceBefore = 0n

    // Mocks
    convexDeposit = {
      ...convexDeposit,
      poolLength: jest.fn().mockResolvedValue(2),
      poolInfo: jest.fn().mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""]).mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
      withdraw: jest.fn().mockResolvedValue(true)
    }

    curveRewardsClass = {
      ...curveRewardsClass,
      withdraw: jest.fn()
    }
    
    curveLpTokenClass = {
      ...curveLpTokenClass,
      balanceOf: jest.fn().mockResolvedValueOnce(BigNumber.from(balanceBefore)).mockResolvedValueOnce(BigNumber.from(withdrawValue))
    }
    
    curveLpTokenERC20 = {
      ...curveLpTokenERC20,
      name: jest.fn().mockResolvedValueOnce(underlyingAssetName),
      symbol: jest.fn().mockResolvedValueOnce(underlyingAssetSymbol),
      decimals: jest.fn().mockResolvedValueOnce(underlyingAssetDecimals),
    }

    IConvexDeposit__factory.connect = () => convexDeposit as any
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any;
    IConvexToken__factory.connect = () => convexTokenClass as any
    ICurveRewards__factory.connect = () => curveRewardsClass as any
    ICurveLpToken__factory.connect = () => curveLpTokenClass as any
    IERC20Metadata__factory.connect = () => curveLpTokenERC20 as any
    
    const convexStakingBridge = ConvexBridgeData.create({} as any, EthAddress.random(), EthAddress.fromString(convexDepositAddr))

    // mock an interaction
    convexStakingBridge.interactions = [{
      id: virtualAsset.id,
      representedConvexToken: convexToken1
    }]


    const expectedOutput = await convexStakingBridge.getUnderlyingAmount(virtualAsset, withdrawValue)

    expect(expectedOutput).toStrictEqual({
      address: curveLpToken.erc20Address,
      name: underlyingAssetName,
      symbol: underlyingAssetSymbol,
      decimals: underlyingAssetDecimals,
      amount: withdrawValue
    })
  })

  it("should return present value of an interaction", async () => {
    const inputValue = 10n
    // const underlyingAssetName = 'underlyingAssetName'
    // const underlyingAssetSymbol = 'underlyingAssetSymbol'
    // const underlyingAssetDecimals = 18
    // // addresses
    const convexDepositAddr = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"

    // const curveLpToken0 = "0x9fC689CCaDa600B6DF723D9E47D84d76664a1F23"
    // const convexToken0 = "0xA1c3492b71938E144ad8bE4c2fB6810b01A43dD8"
    // const crvRewards0 = "0x8B55351ea358e5Eda371575B031ee24F462d503e"

    // const curveLpToken1 = "0xe7A3b38c39F97E977723bd1239C3470702568e7B"
    const convexToken1 = "0xbE665430e4C439aF6C92ED861939E60A963C6d0c"
    // const crvRewards1 = "0x14F02f3b47B407A7a0cdb9292AA077Ce9E124803"

    // // mocked balances
    // const balanceBefore = 0n

    // // Mocks
    // convexDeposit = {
    //   ...convexDeposit,
    //   poolLength: jest.fn().mockResolvedValue(2),
    //   poolInfo: jest.fn().mockResolvedValueOnce([curveLpToken0, convexToken0, "", crvRewards0, "", ""]).mockResolvedValueOnce([curveLpToken1, convexToken1, "", crvRewards1, "", ""]),
    //   withdraw: jest.fn().mockResolvedValue(true)
    // }

    // curveRewardsClass = {
    //   ...curveRewardsClass,
    //   withdraw: jest.fn()
    // }
    
    // curveLpTokenClass = {
    //   ...curveLpTokenClass,
    //   balanceOf: jest.fn().mockResolvedValueOnce(BigNumber.from(balanceBefore)).mockResolvedValueOnce(BigNumber.from(withdrawValue))
    // }
    
    // curveLpTokenERC20 = {
    //   ...curveLpTokenERC20,
    //   name: jest.fn().mockResolvedValueOnce(underlyingAssetName),
    //   symbol: jest.fn().mockResolvedValueOnce(underlyingAssetSymbol),
    //   decimals: jest.fn().mockResolvedValueOnce(underlyingAssetDecimals),
    // }

    // IConvexDeposit__factory.connect = () => convexDeposit as any

    // IRollupProcessor__factory.connect = () => rollupProcessorContract as any;

    // IConvexToken__factory.connect = () => convexTokenClass as any

    // ICurveRewards__factory.connect = () => curveRewardsClass as any

    // ICurveLpToken__factory.connect = () => curveLpTokenClass as any

    // IERC20Metadata__factory.connect = () => curveLpTokenERC20 as any
    
    const convexStakingBridge = ConvexBridgeData.create({} as any, EthAddress.random(), EthAddress.fromString(convexDepositAddr))

    // mock an interaction
    convexStakingBridge.interactions = [{
      id: virtualAsset.id,
      representedConvexToken: convexToken1
    }]


    const expectedAssetValue = await convexStakingBridge.getInteractionPresentValue(virtualAsset.id, inputValue)

    expect(expectedAssetValue[0]).toStrictEqual({
      assetId: virtualAsset.id,
      value: inputValue
    })
  })
})