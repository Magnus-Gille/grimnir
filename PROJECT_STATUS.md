# Project status

Grimnir is an early-stage reference implementation of a modular personal-AI control plane.

## Ready to explore

- The component boundaries and core data flows are documented.
- The public registry is safe example data and is mechanically blocked from deployment.
- Cross-service contracts cover tenant access, audit emission, and reversible mutations.
- The system-level validation and deployment scripts have regression tests.

## Still evolving

- There is no one-command installer or supported hardware matrix.
- Compatibility between independently versioned components is not yet guaranteed.
- Multi-user isolation and unattended autonomous mutation need deployment-specific threat modelling.
- Optional integrations are documented as contracts rather than required repositories.

Operational state belongs in an ignored `STATUS.md` in each private deployment, not in this public
repository.
