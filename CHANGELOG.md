# Changelog

## [0.4.0](https://github.com/bitiq-io/gitops/compare/v0.3.0...v0.4.0) (2025-11-21)


### Features

* **nostr-site:** add ingress path for http01 ([8a67150](https://github.com/bitiq-io/gitops/commit/8a6715075ed7d2a06c61aef66ccd45c4f6e330ce))


### Bug Fixes

* **cert-manager-config:** prefer crc resolver ([d30f612](https://github.com/bitiq-io/gitops/commit/d30f6129ca2495398d5947009f20f30af385d141))
* **charts:** align toy-service tag parity ([71773c8](https://github.com/bitiq-io/gitops/commit/71773c8e626ea83e7222cb257d2f7da202c42abc))
* **nginx:** enable SSA for signet bundle ([cd3375f](https://github.com/bitiq-io/gitops/commit/cd3375ffa01cbb9fd2e89a7ad651d3327abf8ac2))
* **nginx:** refresh signet site payload ([b28f854](https://github.com/bitiq-io/gitops/commit/b28f854b2a6dbb8d3f6126c0544e2cc3f91074c7))
* **nginx:** ship refreshed signet assets ([e181f6a](https://github.com/bitiq-io/gitops/commit/e181f6ac432bcffdbb6daa37af381fe04b7998b9))
* **nostr-site:** restore route + document dns stub ([e0ae8f6](https://github.com/bitiq-io/gitops/commit/e0ae8f64b2dafcfa8f48fd20c2a01d6796e9d6cd))
* **signet-trailer:** ship refreshed og image assets ([94efc2b](https://github.com/bitiq-io/gitops/commit/94efc2be71e5985ef2459e9af1b867659ea41439))
* **signet:** copy, layout, and deploy ([ad1b561](https://github.com/bitiq-io/gitops/commit/ad1b561cc74b29c7ab918c7787706432b1d925cc))
* **signet:** link to nostr protocol ([83f4c22](https://github.com/bitiq-io/gitops/commit/83f4c221c21816ec955e4c69fbb04ae69dc2ef6d))
* **signet:** speed up hero animations ([6cd4976](https://github.com/bitiq-io/gitops/commit/6cd4976a14de545c502dbf8781d3c1dfae1911bb))
* **signet:** sync seo metadata to deployed html ([ad2875a](https://github.com/bitiq-io/gitops/commit/ad2875a8be467cb706832bfffc34b46483bf3bbf))
* **toy-service:** proxy api via frontend route ([ca572b6](https://github.com/bitiq-io/gitops/commit/ca572b689bde244861244eda4884ce1b4ebe8604))
* **toy-web:** rewrite frontend API endpoint ([59235a0](https://github.com/bitiq-io/gitops/commit/59235a0d778d253924391d555c37842050e0f3fd))
* **umbrella:** pause toy-service image updater loop ([9668b7f](https://github.com/bitiq-io/gitops/commit/9668b7fcd65045ecc158c4a9ec1d32c67a5971cc))
* **vault-dev:** allow bootstrap job to reach service ([97ab2f7](https://github.com/bitiq-io/gitops/commit/97ab2f71be2703ec0ac7daf90819d1ea1abfdc81))
* **vault-dev:** bundle static curl for secret creation ([83a4db5](https://github.com/bitiq-io/gitops/commit/83a4db5ea86991bac73d51ac7ed4cd5df465a9d7))
* **vault-dev:** fetch static curl binary when needed ([a37fa01](https://github.com/bitiq-io/gitops/commit/a37fa012732a89a6e2a225f154afc8913e3b1ebc))
* **vault-dev:** force Argo to replace bootstrap job ([3531951](https://github.com/bitiq-io/gitops/commit/35319512dbb31e44028703e1412ff18a8d40c885))
* **vault-dev:** install curl and use it for secret writes ([a0d4a9c](https://github.com/bitiq-io/gitops/commit/a0d4a9cb1e2df19b08f293374c68a3ef34e92561))
* **vault-dev:** log init failure detail ([46294dc](https://github.com/bitiq-io/gitops/commit/46294dc7a9b04c9ceff4cac28ebe082e40f09275))
* **vault-dev:** override entrypoint to avoid dev mode ([b749b25](https://github.com/bitiq-io/gitops/commit/b749b25171e26f825d99d6f447a91a9babca5331))
* **vault-dev:** repair bootstrap job recovery flow ([bce624e](https://github.com/bitiq-io/gitops/commit/bce624ef201a464cbe3d26a9a1fb990be9ff3cfc))
* **vault-dev:** run server with explicit config ([46c534c](https://github.com/bitiq-io/gitops/commit/46c534c411485ac85dd2da2dc9347a47c3f173d9))

## [0.3.0](https://github.com/bitiq-io/gitops/compare/v0.2.0...v0.3.0) (2025-09-16)


### Features

* **sample-app:** switch to public whoami image; add healthPath support; docs: local runbook notes ([dfce58d](https://github.com/bitiq-io/gitops/commit/dfce58d9f2882e2b006d72bd7afbafa969f00e9b))
* **sample-app:** use public whoami; run on 8080 via args; add healthPath; docs: update local runbook ([92308d1](https://github.com/bitiq-io/gitops/commit/92308d1a001f68c7d9a8361d34c44e1c1bd7d0a9))


### Bug Fixes

* **argocd-apps:** remove goTemplate and use standard placeholders to set destination and parameters ([1c82cfc](https://github.com/bitiq-io/gitops/commit/1c82cfcd05b66857e1de44eb41a1292e9366992b))

## [0.2.0](https://github.com/bitiq-io/gitops/compare/v0.1.0...v0.2.0) (2025-09-10)


### Features

* scaffold GitOps stack (Argo CD + Tekton + sample app) ([f325bdc](https://github.com/bitiq-io/gitops/commit/f325bdc884704d917ba818e82d5dde0bef71b828))
