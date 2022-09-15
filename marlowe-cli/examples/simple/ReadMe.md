# Test of a Simple Contract

[This simple contract](../../../marlowe-contracts/src/Marlowe/Contracts/Trivial.hs) takes as deposit, waits for a notification, makes a payment, waits for another notification, and then closes the contract:

```
When
    [Case
        (Deposit
            (PK "d735da025e42bdfeb92e325fc530da3ac732a47726c6cee666a6ea5a")
            (PK "d735da025e42bdfeb92e325fc530da3ac732a47726c6cee666a6ea5a")
            (Token "" "")
            (Constant 12)
        )
        (When
            [Case
                (Notify TrueObs)
                (Pay
                    (PK "d735da025e42bdfeb92e325fc530da3ac732a47726c6cee666a6ea5a")
                    (Party (PK "d735da025e42bdfeb92e325fc530da3ac732a47726c6cee666a6ea5a"))
                    (Token "" "")
                    (Constant 5)
                    (When
                        [Case
                            (Notify TrueObs)
                            Close ]
                        2582625 Close 
                    )
                )]
            2582624 Close 
        )]
    2582623 Close 
```

![Simple Marlowe Contract](simple-0.png)

## Prerequisites

The environment variable `CARDANO_NODE_SOCKET_PATH` must be set to the path to the cardano node's socket.
See below for how to set `MAGIC` to select the network.

The following tools must be on the PATH:
* [marlowe-cli](../../ReadMe.md)
* [cardano-cli](https://github.com/input-output-hk/cardano-node/blob/master/cardano-cli/README.md)
* [jq](https://stedolan.github.io/jq/manual/)
* sed

Signing and verification keys must be provided below for the bystander and party roles, or they will be created automatically: to do this, set the environment variables `BYSTANDER_PREFIX` and `PARTY_PREFIX` where they appear below.

## Preliminaries

```
: "${FAUCET_ADDRESS:?FAUCET_ADDRESS not set}"
: "${FAUCET_SKEY_FILE:?FAUCET_SKEY_FILE not set}"
```

### Select Network

```
: "${MAGIC:=2}"
```

MAGIC=2

```
SLOT_LENGTH=$(marlowe-cli util slotting --testnet-magic "$MAGIC" --socket-path "$CARDANO_NODE_SOCKET_PATH" | jq .scSlotLength)
SLOT_OFFSET=$(marlowe-cli util slotting --testnet-magic "$MAGIC" --socket-path "$CARDANO_NODE_SOCKET_PATH" | jq .scSlotZeroTime)
```

### Participants

#### The Bystander

The bystander simply provides the minimum ada to be held in the contract while it is active.

```
BYSTANDER_PREFIX="$TREASURY/christopher-marlowe"
BYSTANDER_PREFIX="$TREASURY/christopher-marlowe"
BYSTANDER_NAME="Christopher Marlowe"
BYSTANDER_PAYMENT_SKEY="$BYSTANDER_PREFIX".skey
BYSTANDER_PAYMENT_VKEY="$BYSTANDER_PREFIX".vkey
if [[ ! -e "$BYSTANDER_PAYMENT_SKEY" ]]
then
  cardano-cli address key-gen --signing-key-file "$BYSTANDER_PAYMENT_SKEY"      \
                              --verification-key-file "$BYSTANDER_PAYMENT_VKEY"
fi
BYSTANDER_ADDRESS=$(
  cardano-cli address build --testnet-magic "$MAGIC"                                  \
                            --payment-verification-key-file "$BYSTANDER_PAYMENT_VKEY" \
)
BYSTANDER_PUBKEYHASH=$(
  cardano-cli address key-hash --payment-verification-key-file "$BYSTANDER_PAYMENT_VKEY"
)
marlowe-cli util faucet --testnet-magic "$MAGIC"                  \
                        --socket-path "$CARDANO_NODE_SOCKET_PATH" \
                        --out-file /dev/null                      \
                        --submit 600                              \
                        --lovelace 50000000                       \
                        --faucet-address "$FAUCET_ADDRESS"        \
                        --required-signer "$FAUCET_SKEY_FILE"     \
                        "$BYSTANDER_ADDRESS"
```

```console
TxId "a3178641a34b0f78d8bbc389670a684a5606ab7980e918d26ba88261bd91a0d1"
```

The bystander Christopher Marlowe is the minimum-ADA provider and has the address `addr_test1vzt56ln99prhleyjj94gdlwszuwngdky2ppwsh708ncx0csf4zc8r` and public-key hash `974d7e6528477fe492916a86fdd0171d3436c45042e85fcf3cf067e2`. They have the following UTxOs in their wallet:

```
marlowe-cli util clean --testnet-magic "$MAGIC"                    \
                       --socket-path "$CARDANO_NODE_SOCKET_PATH"   \
                       --required-signer "$BYSTANDER_PAYMENT_SKEY" \
                       --change-address "$BYSTANDER_ADDRESS"       \
                       --out-file /dev/null                        \
                       --submit=600                                \
> /dev/null
cardano-cli query utxo --testnet-magic "$MAGIC" --address "$BYSTANDER_ADDRESS"
```

```console
                           TxHash                                 TxIx        Amount
--------------------------------------------------------------------------------------
95d2cdec1b5116e2e04d076e0e4cc776b7e8b7ea3ad93335c02ec8afb917ce6b     0        49834279 lovelace + TxOutDatumNone
```

We select a UTxO with sufficient funds to use in executing the contract.

```
TX_0_BYSTANDER=$(
marlowe-cli util select --testnet-magic "$MAGIC"                  \
                        --socket-path "$CARDANO_NODE_SOCKET_PATH" \
                        --lovelace-only 20000000                  \
                        "$BYSTANDER_ADDRESS"                      \
| sed -n -e '1{s/^TxIn "\(.*\)" (TxIx \(.*\))$/\1#\2/;p}'
)
```

Christopher Marlowe will spend the UTxO `95d2cdec1b5116e2e04d076e0e4cc776b7e8b7ea3ad93335c02ec8afb917ce6b#0`.

#### The Party

The party deposits and removes funds from the contract.

```
PARTY_PREFIX="$TREASURY/francis-beaumont"
PARTY_NAME="Francis Beaumont"
PARTY_PAYMENT_SKEY="$PARTY_PREFIX".skey
PARTY_PAYMENT_VKEY="$PARTY_PREFIX".vkey
if [[ ! -e "$PARTY_PAYMENT_SKEY" ]]
then
  cardano-cli address key-gen --signing-key-file "$PARTY_PAYMENT_SKEY"      \
                              --verification-key-file "$PARTY_PAYMENT_VKEY"
fi
PARTY_ADDRESS=$(
  cardano-cli address build --testnet-magic "$MAGIC"                              \
                            --payment-verification-key-file "$PARTY_PAYMENT_VKEY" \
)
PARTY_PUBKEYHASH=$(
  cardano-cli address key-hash --payment-verification-key-file "$PARTY_PAYMENT_VKEY"
)
marlowe-cli util faucet --testnet-magic "$MAGIC"                  \
                        --socket-path "$CARDANO_NODE_SOCKET_PATH" \
                        --out-file /dev/null                      \
                        --submit 600                              \
                        --lovelace 50000000                       \
                        --faucet-address "$FAUCET_ADDRESS"        \
                        --required-signer "$FAUCET_SKEY_FILE"     \
                        "$PARTY_ADDRESS"
```

```console
TxId "b543aaf343334eb128888353c11bcac325f5e6d1acabd5ea444659f27114dfe3"
```

The party Francis Beaumont has the address `addr_test1vplnyghksch70t8dqzm2zvugkz468gpn76g3ht6tn2jgcrgc5ydf4` and the public-key hash `7f3222f6862fe7aced00b6a13388b0aba3a033f6911baf4b9aa48c0d`. They have the following UTxOs in their wallet:

```
marlowe-cli util clean --testnet-magic "$MAGIC"                  \
                       --socket-path "$CARDANO_NODE_SOCKET_PATH" \
                       --required-signer "$PARTY_PAYMENT_SKEY"   \
                       --change-address "$PARTY_ADDRESS"         \
                       --out-file /dev/null                      \
                       --submit=600                              \
> /dev/null
cardano-cli query utxo --testnet-magic "$MAGIC" --address "$PARTY_ADDRESS"
```

```console
                           TxHash                                 TxIx        Amount
--------------------------------------------------------------------------------------
22eedeb50b888529d27ad88f3a8511454ddb60c43134d71e00287c7b399f4b73     0        49834279 lovelace + TxOutDatumNone
```

We select the UTxO with the most funds to use in executing the contract.

```
TX_0_PARTY=$(
marlowe-cli util select --testnet-magic "$MAGIC"                  \
                        --socket-path "$CARDANO_NODE_SOCKET_PATH" \
                        --lovelace-only 20000000                  \
                        "$PARTY_ADDRESS"                          \
| sed -n -e '1{s/^TxIn "\(.*\)" (TxIx \(.*\))$/\1#\2/;p}'
)
```

Francis Beaumont will spend the UTxO `22eedeb50b888529d27ad88f3a8511454ddb60c43134d71e00287c7b399f4b73#0`.

### Tip of the Blockchain

```
TIP=$(cardano-cli query tip --testnet-magic "$MAGIC" | jq '.slot')
NOW="$((TIP*SLOT_LENGTH+SLOT_OFFSET))"
HOUR="$((3600*1000))"
```

The tip is at slot 2663427. The current POSIX time implies that the tip of the blockchain should be slightly before slot 2663427. Tests may fail if this is not the case.

## The Contract

The contract has a minimum time and a timeout.

```
TIMEOUT_TIME="$((NOW+24*HOUR))"
```

The contract will automatically close at Fri, 09 Sep 2022 19:50:27 +0000.

The contract also involves various payments.

```
MINIMUM_ADA=3000000
DEPOSIT_LOVELACE=12000000
WITHDRAWAL_LOVELACE=5000000
CLOSE_LOVELACE=$((DEPOSIT_LOVELACE-WITHDRAWAL_LOVELACE))
```

The bystander Christopher Marlowe will provide 3000000 lovelace during the contract's operation, so that it satisfies the minimmum-ADA requirement. The party Francis Beaumont will deposit 12000000 lovelace at the start of the contract. They will wait until notified to withdraw 5000000 lovelace. After another notification, the party Francis Beaumont will withdrawn the remaining 7000000 lovelace and the bystander Christopher Marlowe will receive their 3000000 lovelace back. This is expressed in the Marlowe language [here](../../src/Language/Marlowe/CLI/Examples/Trivial.hs).

We create the contract for the previously specified parameters.

```
marlowe-cli template simple --bystander "PK=$BYSTANDER_PUBKEYHASH"       \
                            --minimum-ada "$MINIMUM_ADA"                 \
                            --party "PK=$PARTY_PUBKEYHASH"               \
                            --deposit-lovelace "$DEPOSIT_LOVELACE"       \
                            --withdrawal-lovelace "$WITHDRAWAL_LOVELACE" \
                            --timeout "$TIMEOUT_TIME"                    \
                            --out-contract-file tx-1.contract            \
                            --out-state-file    tx-1.state
```

## Transaction 1. Create the Contract by Providing the Minimum ADA

First we create a `.marlowe` file that contains the initial information needed to run the contract. The bare size and cost of the script provide a lower bound on the resources that running it will require.

```
marlowe-cli run initialize --testnet-magic "$MAGIC"                  \
                           --socket-path "$CARDANO_NODE_SOCKET_PATH" \
                           --contract-file tx-1.contract             \
                           --state-file    tx-1.state                \
                           --out-file      tx-1.marlowe              \
                           --merkleize                               \
                           --print-stats
```

```console
Validator size: 12383
Base-validator cost: ExBudget {exBudgetCPU = ExCPU 18768100, exBudgetMemory = ExMemory 81700}
```

In particular, we can extract the contract's address from the `.marlowe` file.

```
CONTRACT_ADDRESS=$(jq -r '.tx.marloweValidator.address' tx-1.marlowe)
```

The Marlowe contract resides at address `addr_test1wz0znl0lfq7jqmgduzgsu7ndnjt4npgeg5a75j3upvn7dsq3dwfjv`.

The bystander Christopher Marlowe submits the transaction along with the minimum ADA 3000000 lovelace required for the contract's initial state. Submitting with the `--print-stats` switch reveals the network fee for the contract, the size of the transaction, and the execution requirements, relative to the protocol limits.

```
TX_1=$(
marlowe-cli run execute --testnet-magic "$MAGIC"                    \
                        --socket-path "$CARDANO_NODE_SOCKET_PATH"   \
                        --tx-in "$TX_0_BYSTANDER"                   \
                        --required-signer "$BYSTANDER_PAYMENT_SKEY" \
                        --marlowe-out-file tx-1.marlowe             \
                        --change-address "$BYSTANDER_ADDRESS"       \
                        --out-file tx-1.raw                         \
                        --print-stats                               \
                        --submit=600                                \
| sed -e 's/^TxId "\(.*\)"$/\1/'                                    \
)
```

```console
Fee: Lovelace 185521
Size: 440 / 16384 = 2%
Execution units:
  Memory: 0 / 14000000 = 0%
  Steps: 0 / 10000000000 = 0%
```

The contract received the minimum ADA of 3000000 lovelace from the bystander Christopher Marlowe in the transaction `64f3a3293b361ae01a7f8c2869f72a6aec6dc7f4e0086c4e6fd615842c6d172f`. Here is the UTxO at the contract address:

```
cardano-cli query utxo --testnet-magic "$MAGIC" --address "$CONTRACT_ADDRESS" | sed -n -e "1p;2p;/$TX_1/p"
```

```console
                           TxHash                                 TxIx        Amount
--------------------------------------------------------------------------------------
64f3a3293b361ae01a7f8c2869f72a6aec6dc7f4e0086c4e6fd615842c6d172f     1        3000000 lovelace + TxOutDatumHash ScriptDataInBabbageEra "f143dba268d39f7d18fed863024d27d3cf8baa9701bdc91748d948f8e325b493"
```

Here is the UTxO at the bystander Christopher Marlowe's address:

```
cardano-cli query utxo --testnet-magic "$MAGIC" --address "$BYSTANDER_ADDRESS" | sed -n -e "1p;2p;/$TX_1/p"
```

```console
                           TxHash                                 TxIx        Amount
--------------------------------------------------------------------------------------
64f3a3293b361ae01a7f8c2869f72a6aec6dc7f4e0086c4e6fd615842c6d172f     0        46648758 lovelace + TxOutDatumNone
```

## Transaction 2. Make the Initial Deposit

First we compute the Marlowe input required to make the initial deposit by the party.

```
marlowe-cli run prepare --marlowe-file tx-1.marlowe              \
                        --deposit-account "PK=$PARTY_PUBKEYHASH" \
                        --deposit-party "PK=$PARTY_PUBKEYHASH"   \
                        --deposit-amount "$DEPOSIT_LOVELACE"     \
                        --invalid-before "$NOW"                  \
                        --invalid-hereafter "$((NOW+4*HOUR))"    \
                        --out-file tx-2.marlowe                  \
                        --print-stats
```

```console
Datum size: 184
```

Now the party Francis Beaumont submits the transaction along with their deposit:

```
TX_2=$(
marlowe-cli run execute --testnet-magic "$MAGIC"                  \
                        --socket-path "$CARDANO_NODE_SOCKET_PATH" \
                        --marlowe-in-file tx-1.marlowe            \
                        --tx-in-marlowe "$TX_1"#1                 \
                        --tx-in-collateral "$TX_0_PARTY"          \
                        --tx-in "$TX_0_PARTY"                     \
                        --required-signer "$PARTY_PAYMENT_SKEY"   \
                        --marlowe-out-file tx-2.marlowe           \
                        --change-address "$PARTY_ADDRESS"         \
                        --out-file tx-2.raw                       \
                        --print-stats                             \
                        --submit=600                              \
| sed -e 's/^TxId "\(.*\)"$/\1/'                                  \
)
```

```console
Fee: Lovelace 1070512
Size: 13373 / 16384 = 81%
Execution units:
  Memory: 4056512 / 14000000 = 28%
  Steps: 1072753590 / 10000000000 = 10%
```

The contract received the deposit of 12000000 lovelace from the party Francis Beaumont in the transaction `5d76d67c5cbbeeed341d29b40473d9c229ee81029e75268b4a01e4fb4c1926bb`. Here is the UTxO at the contract address:

```
cardano-cli query utxo --testnet-magic "$MAGIC" --address "$CONTRACT_ADDRESS" | sed -n -e "1p;2p;/$TX_2/p"
```

```console
                           TxHash                                 TxIx        Amount
--------------------------------------------------------------------------------------
5d76d67c5cbbeeed341d29b40473d9c229ee81029e75268b4a01e4fb4c1926bb     1        15000000 lovelace + TxOutDatumHash ScriptDataInBabbageEra "bfc8b4b17dd361f49be25fb6c2ddb98d42e4c778401c42abbaf2fece7f7ef407"
```

Here is the UTxO at the party Francis Beaumont's address:

```
cardano-cli query utxo --testnet-magic "$MAGIC" --address "$PARTY_ADDRESS" | sed -n -e "1p;2p;/$TX_2/p"
```

```console
                           TxHash                                 TxIx        Amount
--------------------------------------------------------------------------------------
5d76d67c5cbbeeed341d29b40473d9c229ee81029e75268b4a01e4fb4c1926bb     0        35263767 lovelace + TxOutDatumNone
5d76d67c5cbbeeed341d29b40473d9c229ee81029e75268b4a01e4fb4c1926bb     2        1500000 lovelace + TxOutDatumHash ScriptDataInBabbageEra "8d1aa164b61adfe03cb52c2a3be3c9d860d17b59dd69080a66a78291a920c9c3"
```

## Transaction 3. Make the First Withdrawal

First we compute the input for the contract to transition forward.

```
marlowe-cli run prepare --marlowe-file tx-2.marlowe           \
                        --notify                              \
                        --invalid-before "$NOW"               \
                        --invalid-hereafter "$((NOW+4*HOUR))" \
                        --out-file tx-3.marlowe               \
                        --print-stats
```

```console
Datum size: 153
Payment 1
  Acccount: PK "7f3222f6862fe7aced00b6a13388b0aba3a033f6911baf4b9aa48c0d"
  Payee: Party (PK "7f3222f6862fe7aced00b6a13388b0aba3a033f6911baf4b9aa48c0d")
  Ada: 5.000000
```

Now the party Francis Beaumont can submit a transaction to withdraw funds:

```
TX_3=$(
marlowe-cli run execute --testnet-magic "$MAGIC"                  \
                        --socket-path "$CARDANO_NODE_SOCKET_PATH" \
                        --marlowe-in-file tx-2.marlowe            \
                        --tx-in-marlowe "$TX_2"#1                 \
                        --tx-in-collateral "$TX_2"#0              \
                        --tx-in "$TX_2"#0                         \
                        --required-signer "$PARTY_PAYMENT_SKEY"   \
                        --marlowe-out-file tx-3.marlowe           \
                        --change-address "$PARTY_ADDRESS"         \
                        --out-file tx-3.raw                       \
                        --print-stats                             \
                        --submit=600                              \
| sed -e 's/^TxId "\(.*\)"$/\1/'                                  \
)
```

```console
Fee: Lovelace 1257175
Size: 13339 / 16384 = 81%
Execution units:
  Memory: 6525470 / 14000000 = 46%
  Steps: 1706598106 / 10000000000 = 17%
```

The contract made a payment of 5000000 lovelace to the party Francis Beaumont in the transaction `f35ef97a76af2295eb9e11e423f44ac999524e4a076625f43776c9e362fa9f84`. Here is the UTxO at the contract address:

```
cardano-cli query utxo --testnet-magic "$MAGIC" --address "$CONTRACT_ADDRESS" | sed -n -e "1p;2p;/$TX_3/p"
```

```console
                           TxHash                                 TxIx        Amount
--------------------------------------------------------------------------------------
f35ef97a76af2295eb9e11e423f44ac999524e4a076625f43776c9e362fa9f84     1        10000000 lovelace + TxOutDatumHash ScriptDataInBabbageEra "1344da750a6ebb05a588d94eee0a663361dd2ae21e65a78e7b06f554968c1b22"
```

Here is the UTxO at the party Francis Beaumont's address:

```
cardano-cli query utxo --testnet-magic "$MAGIC" --address "$PARTY_ADDRESS" | sed -n -e "1p;2p;/$TX_3/p"
```

```console
                           TxHash                                 TxIx        Amount
--------------------------------------------------------------------------------------
f35ef97a76af2295eb9e11e423f44ac999524e4a076625f43776c9e362fa9f84     0        32506592 lovelace + TxOutDatumNone
f35ef97a76af2295eb9e11e423f44ac999524e4a076625f43776c9e362fa9f84     2        5000000 lovelace + TxOutDatumNone
f35ef97a76af2295eb9e11e423f44ac999524e4a076625f43776c9e362fa9f84     3        1500000 lovelace + TxOutDatumHash ScriptDataInBabbageEra "213d6bc2ab4a7c22f442cc1df4b5464789ad2c0ef45f08928cb3f033c148d2bf"
```

## Transaction 4. Close the contract

As in the third transaction, we compute the input for the contract to transition forward.

```
marlowe-cli run prepare --marlowe-file tx-3.marlowe           \
                        --notify                              \
                        --invalid-before "$NOW"               \
                        --invalid-hereafter "$((NOW+4*HOUR))" \
                        --out-file tx-4.marlowe               \
                        --print-stats
```

```console
Datum size: 25
Payment 1
  Acccount: PK "974d7e6528477fe492916a86fdd0171d3436c45042e85fcf3cf067e2"
  Payee: Party (PK "974d7e6528477fe492916a86fdd0171d3436c45042e85fcf3cf067e2")
  Ada: 3.000000
Payment 2
  Acccount: PK "7f3222f6862fe7aced00b6a13388b0aba3a033f6911baf4b9aa48c0d"
  Payee: Party (PK "7f3222f6862fe7aced00b6a13388b0aba3a033f6911baf4b9aa48c0d")
  Ada: 7.000000
```

Now the party Francis Beaumont can submit a transaction to close the contract and disperse the remaining funds:

```
TX_4=$(
marlowe-cli run execute --testnet-magic "$MAGIC"                  \
                        --socket-path "$CARDANO_NODE_SOCKET_PATH" \
                        --marlowe-in-file tx-3.marlowe            \
                        --tx-in-marlowe "$TX_3"#1                 \
                        --tx-in-collateral "$TX_3"#0              \
                        --tx-in "$TX_3"#0                         \
                        --tx-in "$TX_3"#2                         \
                        --required-signer "$PARTY_PAYMENT_SKEY"   \
                        --marlowe-out-file tx-4.marlowe           \
                        --change-address "$PARTY_ADDRESS"         \
                        --out-file tx-4.raw                       \
                        --print-stats                             \
                        --submit=600                              \
| sed -e 's/^TxId "\(.*\)"$/\1/'                                  \
)
```

```console
Fee: Lovelace 991967
Size: 12922 / 16384 = 78%
Execution units:
  Memory: 3244698 / 14000000 = 23%
  Steps: 846634745 / 10000000000 = 8%
```

The closing of the contract paid 7000000 lovelace to the the party Francis Beaumont and 3000000 lovelace to the bystander Christopher Marlowe in the transaction `64fad7a0b747615fde7b6a551eb1dd886f0355ed0be17ea4ab17edc8ba4448be`. There is no UTxO at the contract address:

```
cardano-cli query utxo --testnet-magic "$MAGIC" --address "$CONTRACT_ADDRESS" | sed -n -e "1p;2p;/$TX_1/p;/$TX_2/p;/$TX_3/p;/$TX_4/p"
```

```console
                           TxHash                                 TxIx        Amount
--------------------------------------------------------------------------------------
```

Here is the UTxO at the bystander Christopher Marlowe's address:

```
cardano-cli query utxo --testnet-magic "$MAGIC" --address "$BYSTANDER_ADDRESS" | sed -n -e "1p;2p;/$TX_1/p;/$TX_2/p;/$TX_3/p;/$TX_4/p"
```

```console
                           TxHash                                 TxIx        Amount
--------------------------------------------------------------------------------------
64f3a3293b361ae01a7f8c2869f72a6aec6dc7f4e0086c4e6fd615842c6d172f     0        46648758 lovelace + TxOutDatumNone
64fad7a0b747615fde7b6a551eb1dd886f0355ed0be17ea4ab17edc8ba4448be     2        3000000 lovelace + TxOutDatumNone
```

Here is the UTxO at the party Francis Beaumont's address:

```
cardano-cli query utxo --testnet-magic "$MAGIC" --address "$PARTY_ADDRESS" | sed -n -e "1p;2p;/$TX_1/p;/$TX_2/p;/$TX_3/p;/$TX_4/p"
```

```console
                           TxHash                                 TxIx        Amount
--------------------------------------------------------------------------------------
5d76d67c5cbbeeed341d29b40473d9c229ee81029e75268b4a01e4fb4c1926bb     2        1500000 lovelace + TxOutDatumHash ScriptDataInBabbageEra "8d1aa164b61adfe03cb52c2a3be3c9d860d17b59dd69080a66a78291a920c9c3"
64fad7a0b747615fde7b6a551eb1dd886f0355ed0be17ea4ab17edc8ba4448be     0        36514625 lovelace + TxOutDatumNone
64fad7a0b747615fde7b6a551eb1dd886f0355ed0be17ea4ab17edc8ba4448be     1        7000000 lovelace + TxOutDatumNone
f35ef97a76af2295eb9e11e423f44ac999524e4a076625f43776c9e362fa9f84     3        1500000 lovelace + TxOutDatumHash ScriptDataInBabbageEra "213d6bc2ab4a7c22f442cc1df4b5464789ad2c0ef45f08928cb3f033c148d2bf"
```

## Clean Up

```
cleanup() {
  SRC_SKEY="$1"
  SRC_ADDR="$2"
  DEST_ADDR="$3"
  # Combine all ADA together in the source address
  marlowe-cli util clean \
    --testnet-magic "$MAGIC" \
    --socket-path "$CARDANO_NODE_SOCKET_PATH" \
    --required-signer "$SRC_SKEY" \
    --change-address "$SRC_ADDR" \
    --out-file /dev/null \
    --submit 600
  # Get the TxHash#TxIx of these combined funds in a variable we can use as a
  # --tx-in argument
  TX_CLEANUP=$(
  marlowe-cli util select \
    --all "$SRC_ADDR" \
  | sed -e 's/^TxIn "\(.*\)" (TxIx \(.*\))$/\1#\2/' \
  )
  # Send the funds back to the dest address
  marlowe-cli transaction simple \
    --testnet-magic "$MAGIC" \
    --socket-path "$CARDANO_NODE_SOCKET_PATH" \
    --tx-in "$TX_CLEANUP" \
    --required-signer "$SRC_SKEY" \
    --change-address "$DEST_ADDR" \
    --out-file /dev/null \
    --submit 600
}
cleanup "$BYSTANDER_PAYMENT_SKEY" "$BYSTANDER_ADDRESS" "$FAUCET_ADDRESS"
```

```console
TxId "05aef02825895fc037e270f17573b757d9ae2acff7c17d425a932feed82dc0dd"
TxId "a91b50eb714aea26ecf27e1c4fa73de24376d800e05a8105acc56dcb2c568172"
```

```
cleanup "$PARTY_PAYMENT_SKEY" "$PARTY_ADDRESS" "$FAUCET_ADDRESS"
```

```console
TxId "7999ff0ac715cc1bbc0916a8a2c12e2a40f5b97c937fa3ecd00ad54cb50ace03"
TxId "6ae7f8ea90412d6ca7bf3b14bff576fdf6d70382a3818a7253978b58875aa6ed"