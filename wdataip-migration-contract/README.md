# wdataip-migration-contract

One-way 1:1 token migration on BNB Smart Chain (BSC): deposit **wIP** and receive an equal
amount of **WDATAIP**.

## Mechanism

`WdataipMigration` follows the "lock-old / dispense-prefunded-new" pattern (the same approach as
Polygon's audited `PolygonMigration`):

- `wip` and `wdataip` are immutable constructor parameters.
- The contract is **pre-funded** with WDATAIP via a separate transaction — it does not mint.
- `migrate(amount)` pulls `amount` wIP from the caller (`transferFrom`, so approval is required)
  and sends back an equal `amount` of WDATAIP. Both tokens are 18 decimals, so the swap is a raw
  1:1 transfer.
- `rescue(token, to, amount)` is an `Ownable2Step`-gated withdrawal covering both tokens (and any
  tokens sent here by mistake).

Migration is one-way only; there is no reverse path and no minting.

## Tokens (BSC mainnet)

| Token   | Address                                      | Decimals |
| ------- | -------------------------------------------- | -------- |
| wIP     | `0x4d6394bC3031F751EdcE368C189b0E060b527107` | 18       |
| WDATAIP | `0xA37EDed373c5cdF88644db7C6b89f222e756aFB2` | 18       |

## Develop

```sh
forge build
forge test -vvv
forge coverage
forge fmt
```

The fork test is skipped unless `BSC_RPC` is set:

```sh
BSC_RPC=<url> forge test --match-path test/WdataipMigration.fork.t.sol -vvv
```

## Deploy

Copy `.env.example` to `.env` and fill it in, then:

```sh
# Mainnet (token addresses default to the verified mainnet addresses)
forge script script/DeployWdataipMigration.s.sol --rpc-url bsc --broadcast --verify

# Testnet (supply test token addresses via WIP_ADDRESS / WDATAIP_ADDRESS)
forge script script/DeployWdataipMigration.s.sol --rpc-url bsc_testnet --broadcast --verify
```

After deployment, fund the contract by transferring WDATAIP to its address before announcing the
migration.
