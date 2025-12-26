# Changelog

## [0.4.0](https://github.com/bitiq-io/gitops/compare/v0.3.0...v0.4.0) (2025-12-26)


### Features

* **ci-pipelines:** add Tekton build for signet-landing ([a1a1d87](https://github.com/bitiq-io/gitops/commit/a1a1d877f6545fb11004b4e81ce6c4d8335f6e0e))
* **ci-pipelines:** enable signet-landing pipeline via umbrella ([55565a3](https://github.com/bitiq-io/gitops/commit/55565a3f80d0911e69902fbf97b4f372448784d8))
* **nostr-site:** add ingress path for http01 ([8a67150](https://github.com/bitiq-io/gitops/commit/8a6715075ed7d2a06c61aef66ccd45c4f6e330ce))
* **umbrella:** add signet landing static app ([b2129e3](https://github.com/bitiq-io/gitops/commit/b2129e3ef20f2d656cc0a5a897e7858ddf3f3be8))
* **umbrella:** enable image updater for signet-landing ([1eed81f](https://github.com/bitiq-io/gitops/commit/1eed81f1e65a9ee82e81f8de8c746135cc093f85))


### Bug Fixes

* **cert-manager-config:** prefer crc resolver ([d30f612](https://github.com/bitiq-io/gitops/commit/d30f6129ca2495398d5947009f20f30af385d141))
* **charts:** align toy-service tag parity ([71773c8](https://github.com/bitiq-io/gitops/commit/71773c8e626ea83e7222cb257d2f7da202c42abc))
* **charts:** bump nostr-query after couchbase retry ([#122](https://github.com/bitiq-io/gitops/issues/122)) ([85d4d73](https://github.com/bitiq-io/gitops/commit/85d4d73d6632feb7b7f5866e91fdfbc37d0fcbb4))
* **charts:** bump signet-landing to 0.1.1 ([ae201be](https://github.com/bitiq-io/gitops/commit/ae201be1592d0573020ff54a58912acc671addf7))
* **charts:** bump signet-landing to 0.1.2 ([3ff11ee](https://github.com/bitiq-io/gitops/commit/3ff11eea378b64b3a24dfd56b5882c6fe86e2827))
* **charts:** bump signet-landing to 0.1.3 ([656c99a](https://github.com/bitiq-io/gitops/commit/656c99aaf23484fbf2b3c150cec62e8d11d858e8))
* **charts:** bump signet-landing to 0.1.4 ([3803b86](https://github.com/bitiq-io/gitops/commit/3803b86a5d1ae2721760664b6d93525a01e13442))
* **charts:** disable nostr-query networkpolicy locally ([#125](https://github.com/bitiq-io/gitops/issues/125)) ([e34950f](https://github.com/bitiq-io/gitops/commit/e34950fc836f136b9bbaf00f6a7203aa6ab606b6))
* **charts:** open dns cidr for nostr-query ([#124](https://github.com/bitiq-io/gitops/issues/124)) ([ed3d13a](https://github.com/bitiq-io/gitops/commit/ed3d13a2a67e552b5cb7e64e0d9f15724b996ec5))
* **charts:** open dns egress for nostr-query ([#123](https://github.com/bitiq-io/gitops/issues/123)) ([cc7ba2f](https://github.com/bitiq-io/gitops/commit/cc7ba2fe00d594e1a75733a9bd3aaef94bd58fbc))
* **charts:** point nostr-query at couchbase in app namespace ([#121](https://github.com/bitiq-io/gitops/issues/121)) ([88987dd](https://github.com/bitiq-io/gitops/commit/88987dda4a3b14c75b8979b54ab507d82e261bd5))
* **charts:** route signet.ing via landing ingress ([fcfde33](https://github.com/bitiq-io/gitops/commit/fcfde33424b97e6536dfc801e49f605d67c358b1))
* **couchbase:** align services with live analytics ([cddf714](https://github.com/bitiq-io/gitops/commit/cddf71439bb1920f4ee5676d929c7d3c7a8b4ac2))
* **nginx:** drop backend port from redirects ([fa9152a](https://github.com/bitiq-io/gitops/commit/fa9152a5573a78659872bcebf9b0e64d4c7a5482))
* **nginx:** enable SSA for signet bundle ([cd3375f](https://github.com/bitiq-io/gitops/commit/cd3375ffa01cbb9fd2e89a7ad651d3327abf8ac2))
* **nginx:** refresh signet site payload ([b28f854](https://github.com/bitiq-io/gitops/commit/b28f854b2a6dbb8d3f6126c0544e2cc3f91074c7))
* **nginx:** restore paulcapestany.com content ([9397ccd](https://github.com/bitiq-io/gitops/commit/9397ccd0fb9b9a4a325685e125805e651b962cea))
* **nginx:** ship refreshed signet assets ([e181f6a](https://github.com/bitiq-io/gitops/commit/e181f6ac432bcffdbb6daa37af381fe04b7998b9))
* **nostr-site:** restore route + document dns stub ([e0ae8f6](https://github.com/bitiq-io/gitops/commit/e0ae8f64b2dafcfa8f48fd20c2a01d6796e9d6cd))
* **paulcapestany:** use https assets ([2a6db9c](https://github.com/bitiq-io/gitops/commit/2a6db9c94e0d38b88c5a1cbaa829e4020d742643))
* **pipelines:** ignore default sa extras ([dc9a9f4](https://github.com/bitiq-io/gitops/commit/dc9a9f456c2fbe79c7e09ab626eb24148eeb8a77))
* **signet-landing:** seed semver-safe image tag ([d6972ed](https://github.com/bitiq-io/gitops/commit/d6972ed9c22df8421868083ecfa2383ecdcd1d60))
* **signet-trailer:** ship refreshed og image assets ([94efc2b](https://github.com/bitiq-io/gitops/commit/94efc2be71e5985ef2459e9af1b867659ea41439))
* **signet:** copy, layout, and deploy ([ad1b561](https://github.com/bitiq-io/gitops/commit/ad1b561cc74b29c7ab918c7787706432b1d925cc))
* **signet:** link to nostr protocol ([83f4c22](https://github.com/bitiq-io/gitops/commit/83f4c221c21816ec955e4c69fbb04ae69dc2ef6d))
* **signet:** speed up hero animations ([6cd4976](https://github.com/bitiq-io/gitops/commit/6cd4976a14de545c502dbf8781d3c1dfae1911bb))
* **signet:** sync seo metadata to deployed html ([ad2875a](https://github.com/bitiq-io/gitops/commit/ad2875a8be467cb706832bfffc34b46483bf3bbf))
* **toy-service:** proxy api via frontend route ([ca572b6](https://github.com/bitiq-io/gitops/commit/ca572b689bde244861244eda4884ce1b4ebe8604))
* **toy-web:** rewrite frontend API endpoint ([59235a0](https://github.com/bitiq-io/gitops/commit/59235a0d778d253924391d555c37842050e0f3fd))
* **umbrella:** allow commit tags for signet-landing image updates ([070a63d](https://github.com/bitiq-io/gitops/commit/070a63dbe3c73d1b9c65fb79ad553648e2f4b31e))
* **umbrella:** ignore pipeline sa token drift ([de01f03](https://github.com/bitiq-io/gitops/commit/de01f03cf1280ee7b6fc2fb4f0f58dcb667b10b5))
* **umbrella:** pause toy-service image updater loop ([9668b7f](https://github.com/bitiq-io/gitops/commit/9668b7fcd65045ecc158c4a9ec1d32c67a5971cc))
* **umbrella:** protect toy-service updates ([2dd8757](https://github.com/bitiq-io/gitops/commit/2dd87575ea8396a33c46dab0d44b3dbc9549dc79))
* **umbrella:** resume toy-service image updates ([262b7ae](https://github.com/bitiq-io/gitops/commit/262b7ae832b1c169c96da2d0d0b58be3b8c605d3))
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
