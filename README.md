# Juicebox Sips: Juicebox + Sablier v2 Token Streams 

## Summary
A Juicebox [treasury extension](https://docs.juicebox.money/dev/learn/glossary/split-allocator/) which, when added to a projects funding cycle [payout splits](https://docs.juicebox.money/dev/learn/glossary/splits/), receives ETH and optionally swaps into a target token defined by deployer. Sablier v2 Token streams can be created, cancelled, and otherwise managed by the respective Juicebox Project operators via JBSips.

## Use-case & background
Mitigate the trust issues of onboarding new contributors by paying via cancellable [Sablier V2 Token Streams](https://docs.sablier.com/concepts/what-is-sablier).

Also we kinda built this to jam with cool people at Sablier:
[Juicebox Proposal #412](https://www.jbdao.org/s/juicebox/412)

## Design
### Create Flow
* Deploy JBSips and attach it to a projects funding cycle splits
* Payout your Juicebox Project which sends ETH -> ```JBSips.allocate()```
* Project operator calls ```JBSips.deployStreams()``` with their Sablier stream configs
* A [PRB Proxy and Plugin](https://docs.sablier.com/contracts/v2/guides/proxy-architecture/overview) are deployed which allows the JBSips contract to act as a stream management hub
* Streams are then deployed and stored by funding cycle in state variable ```JBSips.streamsByCycleAndAddress```

### Cancel Flow
* Project operator calls ```JBSips.batchCancelStreams()```
* Funds are returned to JBSips
* User can withdraw amounts streamed before cancellation

### Token Dusts
* Project operators can use ```JBSips.withdrawETH()```, ```JBSips.withdrawTokenDust()```, ```JBSips.withdrawAllTokenDust()``` to withdraw any leftover balances.

### Access Control
* Project Operators with [JBOperatable permissions](https://docs.juicebox.money/dev/api/contracts/or-abstract/jboperatable/) in this case ```"SET_SPLITS"```