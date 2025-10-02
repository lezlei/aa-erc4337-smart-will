# AA-Smart-Will: An ERC-4337 Account Abstraction Project

This repository is the third and final project of my [Web3 Arbitrum 14-Day Bootcamp](https://github.com/lezlei/web3-arbitrum-14-day-bootcamp). It builds upon the V1 Smart Will by implementing **Account Abstraction (AA) via ERC-4337** to create a vastly superior user experience for decentralized estate planning.

The goal is a "Smart Will" where owners can set up their inheritance within a Gnosis Safe, and beneficiaries can claim their assets through a simple "magic link"—all without needing to own crypto or pay for gas, thanks to passkey-based smart accounts and a gas-sponsoring relayer.

---
## The Journey: From Concept to a Brutally Debugged dApp

The initial vision was simple: a gasless, passkey-driven inheritance flow. The path to achieving it, however, was an epic debugging saga that touched every layer of the AA stack. This project documents not just the final working code, but the real-world process of troubleshooting a complex, multi-component decentralized application.

The core challenge revolved around getting a **Relayer** to successfully call the `claimInheritance` function, which involved interactions between multiple smart accounts. The journey to the final, working solution involved overcoming:
* **On-Chain Reverts:** Initial failures inside the smart contract logic.
* **Solidity Encoding Bugs:** Subtle but critical errors in how data for the Gnosis Safe contracts was being constructed (`setupData`).
* **Environment Hell:** Mismatches between ERC-4337 v0.6 and v0.7 standards, and unpredictable behavior from using an experimental EVM version (`--hardfork prague`).
* **Gnosis Safe Itself:** Discovering a fundamental architectural limitation in Gnosis Safe, where a UserOperation executed by one Safe cannot, through a module, reliably create or command another Safe due to re-entrancy protections.

The breakthrough came from isolating the on-chain logic with a simple debug script, which proved the contract was sound and the issue was the **execution context**. The final, proven architecture uses an EOA Relayer to break the problematic `Safe -> Module -> Safe` call chain, and instead uses `EOA -> Module -> Safe`.

---
## Project Components

This dApp is composed of an on-chain engine (the smart contract) and several off-chain services that bring it to life.

### Part 1: Completed & Proven Backbone ✅

The core on-chain logic and a full end-to-end simulation of the off-chain flow are complete and working.

#### `WillModule.sol` (The On-Chain Engine)
This is the heart of the dApp—the immutable rulebook on the blockchain. It's designed to be an add-on "module" for a Gnosis Safe.

**Core Functions:**
* `createWill(uint256 _timeoutInDays)`: Initializes a will for the owner's Safe, setting the inactivity timer.
* `addBeneficiary(bytes32 _beneficiary, uint256 _amount)`: Adds a beneficiary and their inheritance amount to the will.
* `ping()`: Allows the owner to reset their inactivity timer, proving they are still active.
* `claimInheritance(address _ownerSafeAddress, string calldata _beneficiarySecret, address _newBeneficiarySafe)`: The public function called by a relayer. It validates that the timeout has expired and the secret is correct, then commands the owner's Safe to transfer the inheritance to the beneficiary's pre-existing Safe address.

#### The Simulation & Relayer Scripts (The Backend Blueprint)
The `typescript-client` folder contains the off-chain logic, written in TypeScript. This is a fully working prototype of the dApp's backend.

* `02_userSimulation.ts`: This script proves the entire end-to-end flow. It simulates:
    1.  An **Owner** creating a Safe, enabling the `WillModule`, and adding a beneficiary.
    2.  A **Beneficiary** getting a new Safe account created for them.
    3.  A **Relayer EOA** being funded and successfully calling `claimInheritance` to transfer the funds.
* `04_debugClaimEvent.ts`: The crucial diagnostic tool that proved the `WillModule.sol` logic was correct by calling it directly from an EOA, which ultimately helped isolate the Gnosis Safe execution context issue.

### Part 2: Remaining Elements For Full dApp

With the on-chain and relayer logic proven, the following off-chain components are needed to create the full user-facing product.

#### The Frontend (The User Interface)
A web application where users interact with the dApp. It would have two main user journeys:
* **For Owners:** A dashboard to connect their Safe, create a will, manage beneficiaries, deposit gas funds, and "ping" the contract.
* **For Beneficiaries:** A simple landing page accessed via their "magic link" (`/claim?secret=...`). It would guide them through creating a passkey-based wallet and clicking a single button to claim their funds.

#### The Backend (The Keeper Bot & dApp Brains)
A server that orchestrates the off-chain logic and connects the frontend to the blockchain.
* **API Endpoints:** To handle requests from the frontend 
* **Database:** A critical component to store data that doesn't belong on-chain:
    * Mapping `beneficiarySecret` to the corresponding `ownerSafeAddress`.
    * Tracking the prepaid **gas deposit balance** for each owner.
* **The Relayer:** The EOA relayer logic from our script lives here, securely storing its private key and using it to call `claimInheritance`.
* **Paymaster & Treasury:** For a true AA experience for the *owners*, the backend would integrate a Paymaster (like Pimlico). It would sponsor `createWill` and `ping` transactions for owners who have a positive gas balance in the database. A **Treasury** address would hold these deposits and fund the Relayer EOA for claim transactions.
* **Notification Service:** To automatically email beneficiaries their unique magic link when an owner adds them.

---
## Tech Stack

* **Smart Contracts:** Solidity
* **Testing & Deployment:** Hardhat
* **TypeScript Client:** TypeScript, Node.js
* **Blockchain Interaction:** Viem, `permissionless.js`
* **Local AA Environment:** Docker, Anvil, Alto (Bundler)

---
## Local Setup & Simulation

This repository is structured as a monorepo with the contracts and the TypeScript client in separate folders.

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/lezlei/aa-smart-will.git](https://github.com/lezlei/aa-smart-will.git)
    cd aa-smart-will
    ```

2.  **Start the Local AA Environment:**
    The local environment (Anvil node, bundler) is managed with Docker.
    ```bash
    cd local-env
    docker-compose up --build -d
    ```

3.  **Deploy the Smart Contract:**
    Navigate to the contracts folder, install dependencies, and deploy `WillModule.sol`.
    ```bash
    cd ../solidity-contracts
    forge install
    forge script script/DeployWillModule.s.sol --rpc-url [http://127.0.0.1:8545](http://127.0.0.1:8545) --broadcast
    ```
    * **Crucially, copy the new `WillModule` contract address** from the output.

4.  **Configure and Run the Simulation:**
    * Navigate to the client folder and install dependencies:
        ```bash
        cd ../typescript-client
        npm install
        ```
    * Paste the new `WillModule` contract address into the `WILL_MODULE_ADDRESS` constant in `scripts/02_userSimulation.ts`.
    * Make sure you have copied the latest compiled ABI from `solidity-contracts/out/WillModule.sol/WillModule.json` to `typescript-client/abis/WillModule.json`.
    * Run the full end-to-end simulation:
        ```bash
        npx tsx scripts/02_userSimulation.ts
        ```