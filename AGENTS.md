# Seba Project Rules

Project-specific development rules. See `~/.claude/AGENTS.md` for global standards.

## Project Overview

Seba is a protocol enabling solo Ethereum validators to unlock perpetual yield from their execution rewards. By committing their rewards for a fixed period, validators can graduate and receive yield-bearing shares that continue to generate rewards indefinitely.

## Tech Stack

| Component | Technology |
|-----------|------------|
| Smart Contracts | Solidity |
| Tests | BTT from Paul R Berg |
| Dev framework | Foundry |

## Commands

```bash
# Development
yarn install         # install dependencies
forge compile        # compile contracts
forge test           # run tests
```

## Project Structure

```
hero_boost/
├── audits/          # Audit reports
├── broadcast/       # Broadcasted transactions
├── images/          # Images
├── script/          # Deploy and other scripts
├── src/             # Smart contracts and interfaces
│   ├── interfaces/  # Interfaces
│   ├── mocks/       # Mocks
│   └── vendor/      # Vendor contracts used
└── tests/           # Smart contract tests
```

## Architecture Reference

- See `README.md` for detailed documentation

## User Documentation

- User documentation can be found at https://docs.heroglyphs.com/seba

## Smart Contract Conventions

- Use interfaces for each contract
- Use Solidity v0.8.28
- Create full NATSPEC
- Prettier and linting should succeed
- Make use of trailofbits claude plugins for development and audits

## Testing

- Tests in `tests/` folder
- Every contract should have a test folder under `tests/`
- Every method should have a test folder under the contracts test folder
- Branching tree tests should be used by Paul R Berg
- **CRITICAL** every branch should be tested
- **CRITICAL** 100% line covereage should be reached
