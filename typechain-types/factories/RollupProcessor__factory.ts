/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { PromiseOrValue } from "../common.js";
import type {
  RollupProcessor,
  RollupProcessorInterface,
} from "../RollupProcessor.js";

const _abi = [
  {
    inputs: [
      {
        internalType: "address",
        name: "_bridgeProxyAddress",
        type: "address",
      },
    ],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    inputs: [],
    name: "INSUFFICIENT_ETH_PAYMENT",
    type: "error",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "uint256",
        name: "bridgeCallData",
        type: "uint256",
      },
      {
        indexed: true,
        internalType: "uint256",
        name: "nonce",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "totalInputValue",
        type: "uint256",
      },
    ],
    name: "AsyncDefiBridgeProcessed",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "uint256",
        name: "bridgeCallData",
        type: "uint256",
      },
      {
        indexed: true,
        internalType: "uint256",
        name: "nonce",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "totalInputValue",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "totalOutputValueA",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "totalOutputValueB",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "bool",
        name: "result",
        type: "bool",
      },
    ],
    name: "DefiBridgeProcessed",
    type: "event",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "bridgeAddress",
        type: "address",
      },
      {
        components: [
          {
            internalType: "uint256",
            name: "id",
            type: "uint256",
          },
          {
            internalType: "address",
            name: "erc20Address",
            type: "address",
          },
          {
            internalType: "enum AztecTypes.AztecAssetType",
            name: "assetType",
            type: "uint8",
          },
        ],
        internalType: "struct AztecTypes.AztecAsset",
        name: "inputAssetA",
        type: "tuple",
      },
      {
        components: [
          {
            internalType: "uint256",
            name: "id",
            type: "uint256",
          },
          {
            internalType: "address",
            name: "erc20Address",
            type: "address",
          },
          {
            internalType: "enum AztecTypes.AztecAssetType",
            name: "assetType",
            type: "uint8",
          },
        ],
        internalType: "struct AztecTypes.AztecAsset",
        name: "inputAssetB",
        type: "tuple",
      },
      {
        components: [
          {
            internalType: "uint256",
            name: "id",
            type: "uint256",
          },
          {
            internalType: "address",
            name: "erc20Address",
            type: "address",
          },
          {
            internalType: "enum AztecTypes.AztecAssetType",
            name: "assetType",
            type: "uint8",
          },
        ],
        internalType: "struct AztecTypes.AztecAsset",
        name: "outputAssetA",
        type: "tuple",
      },
      {
        components: [
          {
            internalType: "uint256",
            name: "id",
            type: "uint256",
          },
          {
            internalType: "address",
            name: "erc20Address",
            type: "address",
          },
          {
            internalType: "enum AztecTypes.AztecAssetType",
            name: "assetType",
            type: "uint8",
          },
        ],
        internalType: "struct AztecTypes.AztecAsset",
        name: "outputAssetB",
        type: "tuple",
      },
      {
        internalType: "uint256",
        name: "totalInputValue",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "interactionNonce",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "auxInputData",
        type: "uint256",
      },
    ],
    name: "convert",
    outputs: [
      {
        internalType: "uint256",
        name: "outputValueA",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "outputValueB",
        type: "uint256",
      },
      {
        internalType: "bool",
        name: "isAsync",
        type: "bool",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    name: "defiInteractions",
    outputs: [
      {
        internalType: "address",
        name: "bridgeAddress",
        type: "address",
      },
      {
        components: [
          {
            internalType: "uint256",
            name: "id",
            type: "uint256",
          },
          {
            internalType: "address",
            name: "erc20Address",
            type: "address",
          },
          {
            internalType: "enum AztecTypes.AztecAssetType",
            name: "assetType",
            type: "uint8",
          },
        ],
        internalType: "struct AztecTypes.AztecAsset",
        name: "inputAssetA",
        type: "tuple",
      },
      {
        components: [
          {
            internalType: "uint256",
            name: "id",
            type: "uint256",
          },
          {
            internalType: "address",
            name: "erc20Address",
            type: "address",
          },
          {
            internalType: "enum AztecTypes.AztecAssetType",
            name: "assetType",
            type: "uint8",
          },
        ],
        internalType: "struct AztecTypes.AztecAsset",
        name: "inputAssetB",
        type: "tuple",
      },
      {
        components: [
          {
            internalType: "uint256",
            name: "id",
            type: "uint256",
          },
          {
            internalType: "address",
            name: "erc20Address",
            type: "address",
          },
          {
            internalType: "enum AztecTypes.AztecAssetType",
            name: "assetType",
            type: "uint8",
          },
        ],
        internalType: "struct AztecTypes.AztecAsset",
        name: "outputAssetA",
        type: "tuple",
      },
      {
        components: [
          {
            internalType: "uint256",
            name: "id",
            type: "uint256",
          },
          {
            internalType: "address",
            name: "erc20Address",
            type: "address",
          },
          {
            internalType: "enum AztecTypes.AztecAssetType",
            name: "assetType",
            type: "uint8",
          },
        ],
        internalType: "struct AztecTypes.AztecAsset",
        name: "outputAssetB",
        type: "tuple",
      },
      {
        internalType: "uint256",
        name: "totalInputValue",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "interactionNonce",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "auxInputData",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "outputValueA",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "outputValueB",
        type: "uint256",
      },
      {
        internalType: "bool",
        name: "finalised",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "interactionNonce",
        type: "uint256",
      },
    ],
    name: "getDefiInteractionBlockNumber",
    outputs: [
      {
        internalType: "uint256",
        name: "blockNumber",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "nonce",
        type: "uint256",
      },
    ],
    name: "getDefiResult",
    outputs: [
      {
        internalType: "bool",
        name: "finalised",
        type: "bool",
      },
      {
        internalType: "uint256",
        name: "outputValueA",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "interactionNonce",
        type: "uint256",
      },
    ],
    name: "processAsyncDefiInteraction",
    outputs: [
      {
        internalType: "bool",
        name: "completed",
        type: "bool",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "interactionNonce",
        type: "uint256",
      },
    ],
    name: "receiveEthFromBridge",
    outputs: [],
    stateMutability: "payable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "bridgeAddress",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "gasLimit",
        type: "uint256",
      },
    ],
    name: "setBridgeGasLimit",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
];

const _bytecode =
  "0x608060405234801561001057600080fd5b5060405161183838038061183883398101604081905261002f91610054565b600080546001600160a01b0319166001600160a01b0392909216919091179055610084565b60006020828403121561006657600080fd5b81516001600160a01b038116811461007d57600080fd5b9392505050565b6117a5806100936000396000f3fe6080604052600436106100705760003560e01c80637753896c1161004e5780637753896c146101265780638188f4681461015d578063d27922e61461018d578063d9b5fb79146101bb57600080fd5b806312a536231461007557806314137e111461008a5780635ad98a1f146100ce575b600080fd5b61008861008336600461128e565b6101f8565b005b34801561009657600080fd5b506100886100a53660046112d0565b73ffffffffffffffffffffffffffffffffffffffff909116600090815260026020526040902055565b3480156100da57600080fd5b5061010a6100e936600461128e565b6000908152600360205260409020600e810154600c9091015460ff90911691565b6040805192151583526020830191909152015b60405180910390f35b34801561013257600080fd5b5061014661014136600461128e565b61021e565b60405161011d9b9a9998979695949392919061139f565b34801561016957600080fd5b5061017d61017836600461128e565b61045e565b604051901515815260200161011d565b34801561019957600080fd5b506101ad6101a836600461128e565b6108d2565b60405190815260200161011d565b3480156101c757600080fd5b506101db6101d6366004611446565b6108e5565b60408051938452602084019290925215159082015260600161011d565b600081815260016020526040812080543492906102169084906114ce565b909155505050565b600360208181526000928352604092839020805484516060810186526001830180548252600284015473ffffffffffffffffffffffffffffffffffffffff80821696840196909652949092169592949093919284019174010000000000000000000000000000000000000000900460ff169081111561029f5761029f6112fa565b60038111156102b0576102b06112fa565b90525060408051606081018252600384810180548352600486015473ffffffffffffffffffffffffffffffffffffffff8116602085015294959492939092908401917401000000000000000000000000000000000000000090910460ff169081111561031e5761031e6112fa565b600381111561032f5761032f6112fa565b905250604080516060810182526005840180548252600685015473ffffffffffffffffffffffffffffffffffffffff81166020840152939493919290919083019074010000000000000000000000000000000000000000900460ff16600381111561039c5761039c6112fa565b60038111156103ad576103ad6112fa565b905250604080516060810182526007840180548252600885015473ffffffffffffffffffffffffffffffffffffffff81166020840152939493919290919083019074010000000000000000000000000000000000000000900460ff16600381111561041a5761041a6112fa565b600381111561042b5761042b6112fa565b9052506009820154600a830154600b840154600c850154600d860154600e90960154949593949293919290919060ff168b565b6000818152600360205260408120805473ffffffffffffffffffffffffffffffffffffffff166104ef576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152601e60248201527f526f6c6c757020436f6e74726163743a20554e4b4e4f574e5f4e4f4e4345000060448201526064015b60405180910390fd5b8054600a820154600b8301546040517f9b07d3420000000000000000000000000000000000000000000000000000000081526000938493849373ffffffffffffffffffffffffffffffffffffffff90921692639b07d3429261056a9260018a019260038b019260058c019260078d0192909190600401611545565b6060604051808303816000875af1158015610589573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906105ad919061159f565b9250925092508094506000821180156105f657506000600885015474010000000000000000000000000000000000000000900460ff1660038111156105f4576105f46112fa565b145b15610683576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152602c60248201527f4e6f6e2d7a65726f206f75747075742076616c7565206f6e206e6f6e2d65786960448201527f7374616e7420617373657421000000000000000000000000000000000000000060648201526084016104e6565b8215801561068f575081155b15610727578354604080516060810182526001870180548252600288015473ffffffffffffffffffffffffffffffffffffffff808216602085015261072295169383019074010000000000000000000000000000000000000000900460ff1660038111156106ff576106ff6112fa565b6003811115610710576107106112fa565b9052506009870154600a880154610a52565b61083d565b8354604080516060810182526005870180548252600688015473ffffffffffffffffffffffffffffffffffffffff80821660208501526107b295169383019074010000000000000000000000000000000000000000900460ff166003811115610792576107926112fa565b60038111156107a3576107a36112fa565b815250508587600a0154610a52565b8354604080516060810182526007870180548252600888015473ffffffffffffffffffffffffffffffffffffffff808216602085015261083d95169383019074010000000000000000000000000000000000000000900460ff16600381111561081d5761081d6112fa565b600381111561082e5761082e6112fa565b815250508487600a0154610a52565b600a840154600985015460408051918252602082018690528101849052600160608201526000907f1ccb5390975e3d07503983a09c3b6a5d11a0e40c4cb4094a7187655f643ef7b49060800160405180910390a350600e830180547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00166001179055600c830191909155600d90910155919050565b60006108df6020836115dd565b92915050565b6000828152600360205260408120600b01548190819015610988576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152602b60248201527f526f6c6c757020436f6e74726163743a20494e544552414354494f4e5f414c5260448201527f454144595f45584953545300000000000000000000000000000000000000000060648201526084016104e6565b60408051610120810190915273ffffffffffffffffffffffffffffffffffffffff8c168152600190600090602081016109c6368f90038f018f611618565b81526020016109da368e90038e018e611618565b81526020016109ee368d90038d018d611618565b8152602001610a02368c90038c018c611618565b81526020018981526020018881526020018781526020018381525090506000610a2a82610b0d565b9050806000015195508060200151945080604001519350505050985098509895505050505050565b81610a5c57610b07565b600183604001516003811115610a7457610a746112fa565b1415610ad657600081815260016020526040902054821115610ac2576040517fcbbf6eca00000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b600081815260016020526040812055610b07565b600283604001516003811115610aee57610aee6112fa565b1415610b07576020830151610b0581863086611226565b505b50505050565b610b33604051806060016040528060008152602001600081526020016000151581525090565b6040805161016081018252835173ffffffffffffffffffffffffffffffffffffffff90811682526020808601518184019081528685015184860152606080880151908501526080808801519085015260a0808801519085015260c080880180519186019190915260e08089015190860152600061010086018190526101208601819052610140860181905290518152600380845290869020855181549086167fffffffffffffffffffffffff0000000000000000000000000000000000000000918216178255925180516001830190815594810151600283018054919097169481168517875597810151969791969095909390927fffffffffffffffffffffff000000000000000000000000000000000000000000909216179074010000000000000000000000000000000000000000908490811115610c7557610c756112fa565b0217905550505060408281015180516003808501918255602083015160048601805473ffffffffffffffffffffffffffffffffffffffff9092167fffffffffffffffffffffffff000000000000000000000000000000000000000083168117825595850151949593949390927fffffffffffffffffffffff000000000000000000000000000000000000000000909216179074010000000000000000000000000000000000000000908490811115610d2f57610d2f6112fa565b021790555050506060820151805160058301908155602082015160068401805473ffffffffffffffffffffffffffffffffffffffff9092167fffffffffffffffffffffffff00000000000000000000000000000000000000008316811782556040850151927fffffffffffffffffffffff000000000000000000000000000000000000000000161774010000000000000000000000000000000000000000836003811115610ddf57610ddf6112fa565b021790555050506080820151805160078301908155602082015160088401805473ffffffffffffffffffffffffffffffffffffffff9092167fffffffffffffffffffffffff00000000000000000000000000000000000000008316811782556040850151927fffffffffffffffffffffff000000000000000000000000000000000000000000161774010000000000000000000000000000000000000000836003811115610e8f57610e8f6112fa565b0217905550505060a0820151600982015560c0820151600a82015560e0820151600b820155610100820151600c820155610120820151600d82015561014090910151600e90910180547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0016911515919091179055815173ffffffffffffffffffffffffffffffffffffffff16600090815260026020526040812054610f38576308f0d180610f60565b825173ffffffffffffffffffffffffffffffffffffffff166000908152600260205260409020545b905060008060008054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1683634bd947a860e01b8760000151886020015189604001518a606001518b608001518c60a001518d60c001518e60e001518f61010001516000604051602401610fee9a999897969594939291906116aa565b604080517fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe08184030181529181526020820180517bffffffffffffffffffffffffffffffffffffffffffffffffffffffff167fffffffff000000000000000000000000000000000000000000000000000000009094169390931790925290516110779190611734565b6000604051808303818686f4925050503d80600081146110b3576040519150601f19603f3d011682016040523d82523d6000602084013e6110b8565b606091505b50915091506040518060600160405280600081526020016000815260200160001515815250935081156111b7576000806000838060200190518101906110fe919061159f565b925092509250806111625760c088015160a089015160408051918252602082018690528101849052600160608201526000907f1ccb5390975e3d07503983a09c3b6a5d11a0e40c4cb4094a7187655f643ef7b49060800160405180910390a36111a7565b8760c0015160007f38ce48f4c2f3454bcf130721f25a4262b2ff2c8e36af937b30edf01ba481eb1d8a60a0015160405161119e91815260200190565b60405180910390a35b9186526020860152151560408501525b8161121e576040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152601260248201527f496e746572616374696f6e204661696c6564000000000000000000000000000060448201526064016104e6565b505050919050565b6040517f23b872dd000000000000000000000000000000000000000000000000000000008152836004820152826024820152816044820152602060006064836000895af190506001600051163d1517808216611286573d6000803e3d6000fd5b505050505050565b6000602082840312156112a057600080fd5b5035919050565b803573ffffffffffffffffffffffffffffffffffffffff811681146112cb57600080fd5b919050565b600080604083850312156112e357600080fd5b6112ec836112a7565b946020939093013593505050565b7f4e487b7100000000000000000000000000000000000000000000000000000000600052602160045260246000fd5b60048110611360577f4e487b7100000000000000000000000000000000000000000000000000000000600052602160045260246000fd5b9052565b8051825273ffffffffffffffffffffffffffffffffffffffff6020820151166020830152604081015161139a6040840182611329565b505050565b73ffffffffffffffffffffffffffffffffffffffff8c16815261026081016113ca602083018d611364565b6113d7608083018c611364565b6113e460e083018b611364565b6113f261014083018a611364565b876101a0830152866101c0830152856101e083015284610200830152836102208301528215156102408301529c9b505050505050505050505050565b60006060828403121561144057600080fd5b50919050565b600080600080600080600080610200898b03121561146357600080fd5b61146c896112a7565b975061147b8a60208b0161142e565b965061148a8a60808b0161142e565b95506114998a60e08b0161142e565b94506114a98a6101408b0161142e565b979a96995094979396956101a085013595506101c0850135946101e001359350915050565b60008219821115611508577f4e487b7100000000000000000000000000000000000000000000000000000000600052601160045260246000fd5b500190565b80548252600181015473ffffffffffffffffffffffffffffffffffffffff8116602084015261139a6040840160ff8360a01c16611329565b6101c08101611554828961150d565b611561606083018861150d565b61156e60c083018761150d565b61157c61012083018661150d565b8361018083015267ffffffffffffffff83166101a0830152979650505050505050565b6000806000606084860312156115b457600080fd5b8351925060208401519150604084015180151581146115d257600080fd5b809150509250925092565b600082611613577f4e487b7100000000000000000000000000000000000000000000000000000000600052601260045260246000fd5b500490565b60006060828403121561162a57600080fd5b6040516060810181811067ffffffffffffffff82111715611674577f4e487b7100000000000000000000000000000000000000000000000000000000600052604160045260246000fd5b60405282358152611687602084016112a7565b602082015260408301356004811061169e57600080fd5b60408201529392505050565b73ffffffffffffffffffffffffffffffffffffffff8b811682526102408201906116d7602084018d611364565b6116e4608084018c611364565b6116f160e084018b611364565b6116ff61014084018a611364565b876101a0840152866101c0840152856101e084015284610200840152808416610220840152509b9a5050505050505050505050565b6000825160005b81811015611755576020818601810151858301520161173b565b81811115611764576000828501525b50919091019291505056fea2646970667358221220f6fac5a9a78d5a2fcdba541f8ceba999f170287d116d1947b08bee217f794c6064736f6c634300080a0033";

type RollupProcessorConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: RollupProcessorConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class RollupProcessor__factory extends ContractFactory {
  constructor(...args: RollupProcessorConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    _bridgeProxyAddress: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<RollupProcessor> {
    return super.deploy(
      _bridgeProxyAddress,
      overrides || {}
    ) as Promise<RollupProcessor>;
  }
  override getDeployTransaction(
    _bridgeProxyAddress: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(_bridgeProxyAddress, overrides || {});
  }
  override attach(address: string): RollupProcessor {
    return super.attach(address) as RollupProcessor;
  }
  override connect(signer: Signer): RollupProcessor__factory {
    return super.connect(signer) as RollupProcessor__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): RollupProcessorInterface {
    return new utils.Interface(_abi) as RollupProcessorInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): RollupProcessor {
    return new Contract(address, _abi, signerOrProvider) as RollupProcessor;
  }
}
