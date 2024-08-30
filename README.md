# bitmap-contracts
Bitmap Game is a metaverse project centered around the bitmap ecosystem. This repo contains the smart contracts used by this project. 

## 1. MerlStake.sol
Used for users to get rewards by staking MERL token. The rewards are tokens including but not limited to THE•BITMAP•TOKEN, RUNE•FINANCIAL etc.

MerlStake address(Merlin Mainnet): 
```
0xb311c4b8091aff30Bb928b17Cc59Ce5D8775b13A
```
MERL token address(Merlin Mainnet): 
```
0x5c46bFF4B38dc1EAE09C5BAc65872a1D8bc87378
```


## 2. BitmapRent.sol
Used for users to rent bitmap blocks by depositing THE•BITMAP•TOKEN. The rent fee is caculated from time to time and paid via THE•BITMAP•TOKEN.
All the collected rent fee is shared with all staking users via MerlStake.sol

BitmapRent address(Merlin Mainnet): 
```
0x8567bD39b8870990a2cA14Df3102a00A7d72f7E3
```
THE•BITMAP•TOKEN token address(Merlin Mainnet): 
```
0x7b0400231Cddf8a7ACa78D8c0483890cd0c6fFD6
```


## 3.GeneralRent.sol
Used for users to rent various kinds of game props by depositing specific tokens.

