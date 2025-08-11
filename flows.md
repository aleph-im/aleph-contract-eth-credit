# 1. Objective

This document outlines a proposal to improve and extend Aleph’s decentralized payment infrastructure by integrating fiat on-ramp providers into our platform via a unified Payment API, indexing on-chain token transfers, and enabling automated credit calculation and token redistribution through smart contracts and scheduled processes.

# 2. Scope of Improvement

The scope includes:

- Creating a Payment API to manage interactions with fiat on-ramp providers.
- Implementing a robust Indexer to monitor ERC-20 Transfer events (USDC).
- Enhancing the Node Status Server to process credit calculations based on indexed transfers.
- Introducing a Smart Contract Distribution System that:
- Swaps accumulated USDC to ALEPH tokens.
- Redistributes ALEPH to predefined reward pools.

# 3. Architecture Overview

The architecture is composed of the following core components:

## 3.1 Payment API

- Handles initiation of payments via third-party fiat on-ramp providers.
- Listens to provider webhooks for status updates and transaction hashes.
- Performs reverse address resolution using provider APIs to associate on-chain transfers with user identities.
- Persists all payment metadata and statuses in a relational DB.

## 3.2 Indexer

- Subscribes to ERC-20 Transfer events of the USDC token.
- Indexes transactions targeting the Aleph contract.
- Coordinates with the Payment API to enrich on-chain data with user identities (for fiat-initiated transfers).
- Stores enriched event logs in a local DB.

## 3.3 Node Status Server

- Periodically queries the indexer for newly recorded USDC transfers.
- Computes equivalent Aleph credits for user addresses.
- Broadcasts credit balances to the network through a standardized POST message.

## 3.4 Distribution Contract

- Every 10 days (or on-demand), the Node Status Server triggers a distribution function.
- The contract swaps USDC → ALEPH via a DEX.
- ALEPH is then distributed to various pools (community, devs, rewards, burn, etc.) based on predefined percentages.

# 4. Sequence Flows

## 4.1 User Buys Credits via Direct USDC Transfer

```mermaid
sequenceDiagram
    actor U as User
    participant T as USDC Token
    participant I as Indexer
    participant N as Node Status
    participant CCN

    U->>+T: POST: Transfer(from: user_address, to: aleph_contract_address)
    T--)+I: EVENT: Transfer(from, to, value, tx_hash, timestamp)
    I->>-I: Index Transfer events
    T->>-U: RES: Success
    loop Every ten minutes
        N->>+I: GET: Transfers(to: aleph_contract_address, from: last_time(), until: now())
        I->>-N: RES: Transfer(from, to, value)[]
        activate N
        N->>N: calculate credits for addresses
        deactivate N
        N--)+CCN: POST: broadcast POST msg with credits
        activate CCN
        CCN->>CCN: Update credit balance table
        deactivate CCN
    end
```

### Key Notes:

- Fully on-chain user flow.
- Credits are calculated based on incoming USDC transfers directly from the user wallet.

## 4.2 User Buys Credits via Fiat On-Ramp

```mermaid
sequenceDiagram
    actor U as User
    participant P as Payments API
    actor O as On-Ramp provider 
    participant T as USDC Token
    participant I as Indexer
    participant N as Node Status
    participant CCN

    U->>+P: POST: Init payment(from: user_address, to: aleph_contract_address)
    P->>+O: POST: Init payment
    O->>-P: RES: Payment config
    P->>P: Save payment config in DB
    P->>-U: RES: Payment config (url, payment_id)

    U->>+O: POST: Submit KYC and Payment (card, SEPA, fiat)
    O->>+T: POST: Transfer(from: provider_address, to: aleph_contract_address)
    T--)+I: EVENT: Transfer(from, to, value, tx_hash, timestamp)
    T->>-O: RES: Success
    
    O--)+P: WEBHOOK: Payment status (payment_id, payment_status, tx_hash)
    P->>-P: Save payment info and status in DB
    O->>-U: RES: Payment complete

    I->>+P: GET: lookup user_address from tx_hash <br/> (when "from" address is in provider_addresses whitelist)
    P->>-I: RES: user_address
    I->>-I: Index Transfer events

    loop Every ten minutes
        N->>+I: GET: Transfers(to: aleph_contract_address, from: last_time(), until: now())
        I->>-N: RES: Transfer(from, to, value)[]
        N->>N: calculate credits for addresses
        N--)+CCN: POST: broadcast POST msg with credits
        activate CCN
        CCN->>CCN: Update credit balance table
        deactivate CCN
    end
```

### Key Notes:

- Off-chain-to-on-chain flow.
- The Payment API bridges identity resolution and payment statuses.
- Credit assignment requires coordination between on-chain events and off-chain data.

## 4.3 Distribution of ALEPH Tokens

```mermaid
sequenceDiagram
    participant N as Node Status
    participant C as Distribution Contract
    participant D as DEX Contract
    participant T as USDC Token
    participant A as ALEPH Token

    loop Every ten days
        N->>+C: POST: DistributeTokens(Receiver(address, percentage)[])
        C->>+D: POST: Swap(from: USDC, to: ALEPH, value)
        D->>+T: POST: TransferFrom(from: aleph_contract_address, to: dex_address)[]
        T->>-D: RES: Success
        D->>+A: POST: TransferFrom(from: dex_address, to: aleph_contract_address)[]
        A->>-D: RES: Success
        D->>-C: RES: Success
        C->>+A: POST: Transfer(from: aleph_contract_address, to: n_address)[]
        A->>-C: RES: Success
        C->>-N: RES: Success
    end
```

### Key Notes:

- The Node Status Server initiates token distribution every 10 days.
- The smart contract autonomously swaps and redistributes tokens based on fixed percentages.

# 5. Implementation Plan

| Component                       | Description                                                                                                                                                      | Status      | Technical Considerations                                                                                                              | Next Steps                                                                                          |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| **Payment API**                 | A centralized API layer to integrate multiple fiat on-ramp providers. Handles initiation, webhook reception, address resolution, and stores all payment data.    | Planned     | - RESTful design<br>- Webhook authentication<br>- Provider-agnostic schema<br>- Address mapping based on tx\_hash lookup              | - Finalize provider integration contracts<br>- Define DB schema<br>- Implement webhook verification |
| **Payment DB**                  | Stores payment metadata, statuses, KYC links, tx hashes, and user addresses.                                                                                     | Planned     | - Relational DB (PostgreSQL)<br>- Index on `payment_id`, `tx_hash`<br>- Foreign key relations for audit history                       | - Define schema migrations<br>- Implement query layer and indexing                                  |
| **Indexer**                     | A backend service that listens to USDC `Transfer` events from the blockchain. Tags known providers and resolves user addresses when needed.                      | Planned     | - JSON-RPC / WebSocket-based event subscription<br>- Provider whitelist filtering<br>- Retry/resync strategy<br>- Event deduplication | - Complete provider address whitelisting<br>- Implement enrichment pipeline via Payment API         |
| **Event DB**                    | Stores all `Transfer` events (with enrichment metadata) that are directed to the Aleph contract.                                                                 | Planned     | - Partitioned by block timestamp<br>- Indexed by `to_address`, `from_address`, `tx_hash`                                              | - Normalize structure with user metadata<br>- Add archival mechanism                                |
| **Node Status Server**          | Periodically polls the indexer to retrieve new transfers, calculates Aleph credit balances based on USDC transferred, and broadcasts results to the CCN network. | Planned     | - Efficient polling intervals<br>- Idempotent computation<br>- Stable broadcast mechanism                                             | - Finalize polling logic<br>- Validate output format with CCN<br>- Add unit tests                   |
| **Credit Balance DB**           | Stores latest computed Aleph credits for all user addresses, updated every 10 minutes.                                                                           | Planned     | - Write-heavy with low-latency read requirements<br>- TTL or versioned historical balance tracking                                    | - Connect with CCN updates<br>- Monitor drift or inconsistencies                                    |
| **Smart Distribution Contract** | On-chain contract that receives the USDC tokens, swaps them for ALEPH via a DEX, and redistributes tokens to multiple reward pools.                              | Planned     | - Modular & upgradeable<br>- Configurable recipient list and percentages<br>- Uses on-chain DEX (e.g., Uniswap V3 interface)          | - Draft initial Solidity contract<br>- Define reward pool logic<br>- Setup testnet deployment       |
| **DEX Integration**             | Interface with a decentralized exchange to perform USDC → ALEPH swaps.                                                                                           | Planned     | - Use existing on-chain routers<br>- Ensure slippage limits<br>- Multi-step swap path support                                         | - Research optimal DEXs with deep USDC/ALEPH liquidity<br>- Simulate swap operations                |
| **Distribution Trigger**        | Functionality in the Node Status Server that signs and initiates `DistributeTokens()` every 10 days via a configured wallet.                                     | Planned     | - Scheduled cronjob<br>- Secure key handling (signing wallet)<br>- Retry on failure                                                   | - Implement signing flow<br>- Add monitoring for execution status                                   |


# 6. Considerations

- __Security__: Webhook endpoints must validate authenticity; smart contracts must be audited.
- __Scalability__: Indexer and payment resolution should support concurrent, large-volume transactions.
- __Compliance__: Ensure provider integrations meet regional KYC/AML standards.
- __Transparency__: All transactions and distributions are recorded and auditable on-chain.

# 7. Future Improvements

- Integrate L2 payment providers (e.g., Base, Arbitrum).
- Expand support to additional tokens (e.g., stablecoins beyond USDC).
- Enable multi-chain token routing and bridging.
- Integrate analytics and monitoring dashboards.

# 8. Conclusion

This proposal aims to create a seamless bridge between fiat and Web3, providing users with multiple payment options while preserving transparency, decentralization, and automation. It aligns with Aleph’s mission to offer programmable financial infrastructure at scale.

# 9. Refs

- https://docs.transak.com/reference/get-order-by-order-id
- https://docs.banxa.com/reference/retrieve-a-specific-order
- https://docs.inflowpay.com/reference/getpayment