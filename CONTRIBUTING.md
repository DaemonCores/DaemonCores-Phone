# Contributing to DaemonCores-Phone

<p align="center">
  <img src="https://raw.githubusercontent.com/DaemonCores/.github/refs/heads/main/assets/banner.svg" alt="AstralEmu Banner" width="100%"/>
</p>

<p>
  <strong align="left">Simplify and Innovate for Everyone.</strong>
  <a href="https://github.com/DaemonCores/debian-bootc/wiki"><img align="right" src="https://img.shields.io/badge/Wiki-FFFFFF?style=for-the-badge&logoColor=white" alt="Documentation"/></a>
  <a href="https://github.com/orgs/DaemonCores/discussions"><img align="right" src="https://img.shields.io/badge/Community-000000?style=for-the-badge&logoColor=white" alt="Community"/></a>
  <a href="https://github.com/DaemonCores/debian-bootc"><img align="right" src="https://img.shields.io/badge/Base_debian_for_all_project-A81D33?style=for-the-badge&logo=debian&logoColor=white" alt="Debian Bootc"/></a>
  
  <em>Identify gaps and fill them, make improvements where possible, but above all, empower developers to offer more to users.</em>
</p>

---

DaemonCores-Phone is an early implementation. Contributions should improve the verified path from device data to a reproducible boot rather than expand unsupported compatibility claims.

## Useful contributions now

- tests and fixtures for `scripts/probe-to-yaml.py`;
- schema corrections backed by real device data;
- privacy review for the future probe format;
- cleanup of inherited image and package assumptions;
- an explicit architecture matrix for the CI;
- recovery, build, and boot evidence for one owned test device;
- documentation corrections that distinguish implemented and planned work.

## Device submissions

Do not submit a generated descriptor without reviewing every field. A device pull request should include source provenance, pinned revisions, recovery information, and the evidence available for its status.

Never include serial numbers, account identifiers, tokens, private keys, full user partitions, or proprietary files that cannot be redistributed.

## Status claims

The labels `booted`, `partial`, `functional`, and `full` require the evidence defined in [docs/architecture.md](docs/architecture.md). A schema-valid descriptor or successful kernel compilation is not proof that a phone boots.

## Code changes

- Add tests for converter and schema behaviour.
- Make build inputs reproducible and pinned.
- Keep destructive flash operations out of automated defaults.
- Provide a recovery path before asking others to test an image.
- Document tested and untested hardware paths explicitly.
- Update the roadmap and documentation in the same pull request.

Use [SECURITY.md](SECURITY.md) for private vulnerability reports.

---

<p>
  <strong align="left">Made with ⭐ by the DaemonCores community</strong>
  <a href="https://github.com/DaemonCores/debian-bootc/wiki"><img align="right" src="https://img.shields.io/badge/Wiki-FFFFFF?style=for-the-badge&logoColor=white" alt="Documentation"/></a>
  <a href="https://github.com/orgs/DaemonCores/discussions"><img align="right" src="https://img.shields.io/badge/Community-000000?style=for-the-badge&logoColor=white" alt="Community"/></a>
  <a href="https://github.com/DaemonCores/debian-bootc"><img align="right" src="https://img.shields.io/badge/Base_debian_for_all_project-A81D33?style=for-the-badge&logo=debian&logoColor=white" alt="Debian Bootc"/></a>
</p>
