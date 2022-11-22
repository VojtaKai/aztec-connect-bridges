/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer, utils } from "ethers";
import type { Provider } from "@ethersproject/providers";
import type {
  ICompoundERC4626,
  ICompoundERC4626Interface,
} from "../ICompoundERC4626.js";

const _abi = [
  {
    inputs: [],
    name: "cToken",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];

export class ICompoundERC4626__factory {
  static readonly abi = _abi;
  static createInterface(): ICompoundERC4626Interface {
    return new utils.Interface(_abi) as ICompoundERC4626Interface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): ICompoundERC4626 {
    return new Contract(address, _abi, signerOrProvider) as ICompoundERC4626;
  }
}
