# Bitiq GitOps Repository Specification

**Version:** 1.0.0  
**Date:** YYYY-MM-DD  
**Status:** Approved

## Overview

This repository defines the Helm-first GitOps stack for Bitiq environments (local, SNO, prod) driven by Argo CD and Tekton. It provides a consistent, reproducible way to install and manage:
- OpenShift GitOps (Argo CD) and OpenShift Pipelines (Tekton)
- An ApplicationSet that orchestrates an umbrella application per environment
- Sub-apps: Image Updater, CI Pipelines, and a sample app

## Core Functionality

- Bootstrap operators via OLM Subscriptions
- Deploy an ApplicationSet with env-specific values
- Manage CI/CD and automated image updates via Argo CD Image Updater

## Technical Requirements

- OpenShift 4.x with cluster-admin access for bootstrap
- Helm charts under `charts/` for each component
- Make targets for linting and template validation

## Non-Functional Requirements

- Declarative (Git as source of truth)
- Secure (no secrets committed; use sealed/managed secrets patterns)
- Auditable (PRs with Conventional Commits)

## Development Process

- Use branches and PRs for changes
- Validate with `make lint` and `make template`
- Keep `README.md` updated for bootstrap and usage

## Deliverables

- Helm charts for operators, umbrella app, and sub-apps
- CI workflows and triggers configuration
- Documentation and contributors guide (`AGENTS.md`)

## Acceptance Criteria

- All required docs present (README, AGENTS, SPEC, TODO)
- Helm charts lint and template successfully for all envs
- Docs-check workflow passes on PRs

## Change History

- 1.0.0 — Initial specification

