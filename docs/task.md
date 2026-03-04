# Task List for Apple Foundation Model CLI

- [x] Research & Planning
    - [x] Research GenerationOptions API (temperature, sampling)
    - [x] Update Implementation Plan
- [/] Implementation
    - [x] Add CLI arguments for temperature and sampling
    - [x] Integrate GenerationOptions into SystemLanguageModel call
- [x] Verification
    - [x] Verify temperature argument effect
    - [x] Verify sampling argument effect
- [x] CI
    - [x] Add GitHub Actions workflow for Swift lint and build
    - [x] Pin `actions/checkout` to `v6.0.2` commit hash
    - [x] Use fixed `macos-26` runner label in workflow
