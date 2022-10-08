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