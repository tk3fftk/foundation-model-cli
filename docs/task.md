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
- [x] Lint Hotfix (run 22658023020 / job 65672624680)
    - [x] Fix identifier naming violation in `main.swift`
    - [x] Fix line length violation in `main.swift`
    - [x] Remove trailing whitespace in `main.swift`
    - [x] Remove trailing comma warnings in `Package.swift`
