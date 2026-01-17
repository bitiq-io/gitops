# Changelog

## [0.4.0](https://github.com/bitiq-io/gitops/compare/v0.3.0...v0.4.0) (2026-01-17)


### Features

* **charts:** add cluster-capacity GPU app ([#126](https://github.com/bitiq-io/gitops/issues/126)) ([69c8b32](https://github.com/bitiq-io/gitops/commit/69c8b3284e022fb69d2c71eb37b6e9679238c69e))
* **charts:** add OpenShift AI GPU inference stack ([6623fc9](https://github.com/bitiq-io/gitops/commit/6623fc92ea8fdbd0b5d18119cc366b0bcad53160))
* **charts:** scale prod GPU pool to 1 ([#129](https://github.com/bitiq-io/gitops/issues/129)) ([d238b92](https://github.com/bitiq-io/gitops/commit/d238b9201d8685869bbdeac15e38ed8eb0093bfe))
* **ci-pipelines:** add Tekton build for signet-landing ([a1a1d87](https://github.com/bitiq-io/gitops/commit/a1a1d877f6545fb11004b4e81ce6c4d8335f6e0e))
* **ci-pipelines:** enable signet-landing pipeline via umbrella ([55565a3](https://github.com/bitiq-io/gitops/commit/55565a3f80d0911e69902fbf97b4f372448784d8))
* **cluster-capacity:** add NVIDIA GPU console dashboard ([f6376f7](https://github.com/bitiq-io/gitops/commit/f6376f742cd1a9075cfb1c258318fbc487009ea9))
* **nostr-site:** add ingress path for http01 ([8a67150](https://github.com/bitiq-io/gitops/commit/8a6715075ed7d2a06c61aef66ccd45c4f6e330ce))
* **operators:** enable NVIDIA GPU Operator in prod ([#130](https://github.com/bitiq-io/gitops/issues/130)) ([b83c2ff](https://github.com/bitiq-io/gitops/commit/b83c2ff23ef97dcef8e757dcb17593cfc0f00283))
* **signet-llm:** add vLLM serving runtime ([c995925](https://github.com/bitiq-io/gitops/commit/c9959254186aa18b22cecea3aa67a87e5d069c9b))
* **umbrella:** add signet landing static app ([b2129e3](https://github.com/bitiq-io/gitops/commit/b2129e3ef20f2d656cc0a5a897e7858ddf3f3be8))
* **umbrella:** enable image updater for signet-landing ([1eed81f](https://github.com/bitiq-io/gitops/commit/1eed81f1e65a9ee82e81f8de8c746135cc093f85))


### Bug Fixes

* **bootstrap:** defer ArgoCD instance until CRD ready ([b7cdeb4](https://github.com/bitiq-io/gitops/commit/b7cdeb4a663709187ef4aa000c10ebd5704758ce))
* **cert-manager-config:** prefer crc resolver ([d30f612](https://github.com/bitiq-io/gitops/commit/d30f6129ca2495398d5947009f20f30af385d141))
* **charts:** align toy-service tag parity ([71773c8](https://github.com/bitiq-io/gitops/commit/71773c8e626ea83e7222cb257d2f7da202c42abc))
* **charts:** avoid gpu rollout deadlock ([88f600b](https://github.com/bitiq-io/gitops/commit/88f600bc49766bfa4e84b5236155b43bc26546ed))
* **charts:** bump nostr-query after couchbase retry ([#122](https://github.com/bitiq-io/gitops/issues/122)) ([85d4d73](https://github.com/bitiq-io/gitops/commit/85d4d73d6632feb7b7f5866e91fdfbc37d0fcbb4))
* **charts:** bump signet-landing to 0.1.1 ([ae201be](https://github.com/bitiq-io/gitops/commit/ae201be1592d0573020ff54a58912acc671addf7))
* **charts:** bump signet-landing to 0.1.2 ([3ff11ee](https://github.com/bitiq-io/gitops/commit/3ff11eea378b64b3a24dfd56b5882c6fe86e2827))
* **charts:** bump signet-landing to 0.1.3 ([656c99a](https://github.com/bitiq-io/gitops/commit/656c99aaf23484fbf2b3c150cec62e8d11d858e8))
* **charts:** bump signet-landing to 0.1.4 ([3803b86](https://github.com/bitiq-io/gitops/commit/3803b86a5d1ae2721760664b6d93525a01e13442))
* **charts:** disable nostr-query networkpolicy locally ([#125](https://github.com/bitiq-io/gitops/issues/125)) ([e34950f](https://github.com/bitiq-io/gitops/commit/e34950fc836f136b9bbaf00f6a7203aa6ab606b6))
* **charts:** force NVIDIA_VISIBLE_DEVICES ([87b4ca5](https://github.com/bitiq-io/gitops/commit/87b4ca57fee20da896c2069cccb07ac72f3b45ef))
* **charts:** make prod Vault self-contained ([ea3c66c](https://github.com/bitiq-io/gitops/commit/ea3c66c5d5d1f5541f480c57509c349a574b3ebc))
* **charts:** open dns cidr for nostr-query ([#124](https://github.com/bitiq-io/gitops/issues/124)) ([ed3d13a](https://github.com/bitiq-io/gitops/commit/ed3d13a2a67e552b5cb7e64e0d9f15724b996ec5))
* **charts:** open dns egress for nostr-query ([#123](https://github.com/bitiq-io/gitops/issues/123)) ([cc7ba2f](https://github.com/bitiq-io/gitops/commit/cc7ba2fe00d594e1a75733a9bd3aaef94bd58fbc))
* **charts:** point nostr-query at couchbase in app namespace ([#121](https://github.com/bitiq-io/gitops/issues/121)) ([88987dd](https://github.com/bitiq-io/gitops/commit/88987dda4a3b14c75b8979b54ab507d82e261bd5))
* **charts:** prefer host libcuda path ([37ca8e0](https://github.com/bitiq-io/gitops/commit/37ca8e06b51f4b9fb182141859c53538e56ad1ff))
* **charts:** route signet.ing via landing ingress ([fcfde33](https://github.com/bitiq-io/gitops/commit/fcfde33424b97e6536dfc801e49f605d67c358b1))
* **charts:** set LD_LIBRARY_PATH for inference ([cee4191](https://github.com/bitiq-io/gitops/commit/cee419134516560f12aa912b5393fc8f324e52cb))
* **charts:** set runtimeClassName for inference ([6b85734](https://github.com/bitiq-io/gitops/commit/6b85734ace086fd0563c811eeb1f25cd2d9995d9))
* **charts:** switch inference to nvidia-cdi ([5addf13](https://github.com/bitiq-io/gitops/commit/5addf136b42b05db1dd10fd33f2063c806b74eaf))
* **charts:** try nvidia-legacy runtime ([392990a](https://github.com/bitiq-io/gitops/commit/392990aa358125f7a975a3937c73166be4453f31))
* **ci:** disable helm-unittest verify ([#127](https://github.com/bitiq-io/gitops/issues/127)) ([a9604c9](https://github.com/bitiq-io/gitops/commit/a9604c9460807b0b60bab24cf8ecba68042dc640))
* **cluster-capacity:** allow ArgoCD to manage ServiceMonitors ([3758fd2](https://github.com/bitiq-io/gitops/commit/3758fd2aaf1496b0b9e0892d0e7e647b7509ecd9))
* **cluster-capacity:** run prod GPUs on-demand g6e ([d5cb45c](https://github.com/bitiq-io/gitops/commit/d5cb45cbee1d83e3a97ef8dba4fcf146c9d2e8f5))
* **cluster-capacity:** scrape dcgm exporter metrics ([14b6153](https://github.com/bitiq-io/gitops/commit/14b6153361b5048d2c033cc32034a6fe99e6180d))
* **couchbase:** align services with live analytics ([cddf714](https://github.com/bitiq-io/gitops/commit/cddf71439bb1920f4ee5676d929c7d3c7a8b4ac2))
* **gitops:** use helm v4 in CI ([#128](https://github.com/bitiq-io/gitops/issues/128)) ([991dc0f](https://github.com/bitiq-io/gitops/commit/991dc0fbeb8b7bfd641a97d55805a9fd41f2efb4))
* **nginx:** drop backend port from redirects ([fa9152a](https://github.com/bitiq-io/gitops/commit/fa9152a5573a78659872bcebf9b0e64d4c7a5482))
* **nginx:** enable SSA for signet bundle ([cd3375f](https://github.com/bitiq-io/gitops/commit/cd3375ffa01cbb9fd2e89a7ad651d3327abf8ac2))
* **nginx:** refresh signet site payload ([b28f854](https://github.com/bitiq-io/gitops/commit/b28f854b2a6dbb8d3f6126c0544e2cc3f91074c7))
* **nginx:** restore paulcapestany.com content ([9397ccd](https://github.com/bitiq-io/gitops/commit/9397ccd0fb9b9a4a325685e125805e651b962cea))
* **nginx:** ship refreshed signet assets ([e181f6a](https://github.com/bitiq-io/gitops/commit/e181f6ac432bcffdbb6daa37af381fe04b7998b9))
* **nostr-site:** restore route + document dns stub ([e0ae8f6](https://github.com/bitiq-io/gitops/commit/e0ae8f64b2dafcfa8f48fd20c2a01d6796e9d6cd))
* **operators:** allow Argo to apply ClusterPolicy ([#132](https://github.com/bitiq-io/gitops/issues/132)) ([01ea801](https://github.com/bitiq-io/gitops/commit/01ea80103d25cd81383fe66605da5888aeaec5c6))
* **operators:** allow Argo to create NodeFeatureDiscovery ([#136](https://github.com/bitiq-io/gitops/issues/136)) ([ec3b90c](https://github.com/bitiq-io/gitops/commit/ec3b90c68cb9f5b0f62fda9068199b53de7a366e))
* **operators:** avoid ClusterPolicy sync before CRD ([#131](https://github.com/bitiq-io/gitops/issues/131)) ([ffb45c2](https://github.com/bitiq-io/gitops/commit/ffb45c20194e639a989fce09188fd17958987fc7))
* **operators:** default GPU Operator to SingleNamespace ([#134](https://github.com/bitiq-io/gitops/issues/134)) ([2227e91](https://github.com/bitiq-io/gitops/commit/2227e9112343cf0a72991c327ba0cf876c197b89))
* **operators:** enable ArgoCD admin apiKey ([69841d1](https://github.com/bitiq-io/gitops/commit/69841d1d4dad41afabd2f5e21c90e4a3f183e1ae))
* **operators:** install NFD for GPU Operator ([#135](https://github.com/bitiq-io/gitops/issues/135)) ([b6df887](https://github.com/bitiq-io/gitops/commit/b6df8875ffd2a024139563f15f7f4697edc8c455))
* **operators:** satisfy ClusterPolicy required fields ([#133](https://github.com/bitiq-io/gitops/issues/133)) ([7711811](https://github.com/bitiq-io/gitops/commit/77118111bbe6ffb88c3f88bf813b1487541d855a))
* **paulcapestany:** use https assets ([2a6db9c](https://github.com/bitiq-io/gitops/commit/2a6db9c94e0d38b88c5a1cbaa829e4020d742643))
* **pipelines:** ignore default sa extras ([dc9a9f4](https://github.com/bitiq-io/gitops/commit/dc9a9f456c2fbe79c7e09ab626eb24148eeb8a77))
* **signet-landing:** seed semver-safe image tag ([d6972ed](https://github.com/bitiq-io/gitops/commit/d6972ed9c22df8421868083ecfa2383ecdcd1d60))
* **signet-llm:** force nvidia driver library path ([5d498a1](https://github.com/bitiq-io/gitops/commit/5d498a1eb35e92d01060add4a636f21aa1c1b10b))
* **signet-trailer:** ship refreshed og image assets ([94efc2b](https://github.com/bitiq-io/gitops/commit/94efc2be71e5985ef2459e9af1b867659ea41439))
* **signet:** copy, layout, and deploy ([ad1b561](https://github.com/bitiq-io/gitops/commit/ad1b561cc74b29c7ab918c7787706432b1d925cc))
* **signet:** link to nostr protocol ([83f4c22](https://github.com/bitiq-io/gitops/commit/83f4c221c21816ec955e4c69fbb04ae69dc2ef6d))
* **signet:** speed up hero animations ([6cd4976](https://github.com/bitiq-io/gitops/commit/6cd4976a14de545c502dbf8781d3c1dfae1911bb))
* **signet:** sync seo metadata to deployed html ([ad2875a](https://github.com/bitiq-io/gitops/commit/ad2875a8be467cb706832bfffc34b46483bf3bbf))
* **toy-service:** proxy api via frontend route ([ca572b6](https://github.com/bitiq-io/gitops/commit/ca572b689bde244861244eda4884ce1b4ebe8604))
* **toy-service:** use /healthz for probes ([2bd4676](https://github.com/bitiq-io/gitops/commit/2bd467691952344b266f10ca7832f7d72669e3a4))
* **toy-web:** rewrite frontend API endpoint ([59235a0](https://github.com/bitiq-io/gitops/commit/59235a0d778d253924391d555c37842050e0f3fd))
* **umbrella:** allow commit tags for signet-landing image updates ([070a63d](https://github.com/bitiq-io/gitops/commit/070a63dbe3c73d1b9c65fb79ad553648e2f4b31e))
* **umbrella:** grant Argo CD KServe RBAC ([cce0b53](https://github.com/bitiq-io/gitops/commit/cce0b53acd092516d26b0b65d6f1c8114e3b70db))
* **umbrella:** ignore pipeline sa token drift ([de01f03](https://github.com/bitiq-io/gitops/commit/de01f03cf1280ee7b6fc2fb4f0f58dcb667b10b5))
* **umbrella:** pause toy-service image updater loop ([9668b7f](https://github.com/bitiq-io/gitops/commit/9668b7fcd65045ecc158c4a9ec1d32c67a5971cc))
* **umbrella:** protect toy-service updates ([2dd8757](https://github.com/bitiq-io/gitops/commit/2dd87575ea8396a33c46dab0d44b3dbc9549dc79))
* **umbrella:** resume toy-service image updates ([262b7ae](https://github.com/bitiq-io/gitops/commit/262b7ae832b1c169c96da2d0d0b58be3b8c605d3))
* **vault-dev:** allow bootstrap job to reach service ([97ab2f7](https://github.com/bitiq-io/gitops/commit/97ab2f71be2703ec0ac7daf90819d1ea1abfdc81))
* **vault-dev:** auto-unseal on restart ([74fd324](https://github.com/bitiq-io/gitops/commit/74fd324538e4462953ab293b9d8efcbff1b06ffc))
* **vault-dev:** bundle static curl for secret creation ([83a4db5](https://github.com/bitiq-io/gitops/commit/83a4db5ea86991bac73d51ac7ed4cd5df465a9d7))
* **vault-dev:** enable TokenReview for k8s auth ([07c3033](https://github.com/bitiq-io/gitops/commit/07c3033ad39de6861b380e2264bc1aabf7264a2c))
* **vault-dev:** fetch static curl binary when needed ([a37fa01](https://github.com/bitiq-io/gitops/commit/a37fa012732a89a6e2a225f154afc8913e3b1ebc))
* **vault-dev:** force Argo to replace bootstrap job ([3531951](https://github.com/bitiq-io/gitops/commit/35319512dbb31e44028703e1412ff18a8d40c885))
* **vault-dev:** force recreate bootstrap Job ([8ff40f4](https://github.com/bitiq-io/gitops/commit/8ff40f49dd93fafc966a5f584b1d2c9c08f37b01))
* **vault-dev:** grant VCO sudo capabilities ([4fccaaa](https://github.com/bitiq-io/gitops/commit/4fccaaa1b6018ae698b17616cc6373aed5420c42))
* **vault-dev:** install curl and use it for secret writes ([a0d4a9c](https://github.com/bitiq-io/gitops/commit/a0d4a9cb1e2df19b08f293374c68a3ef34e92561))
* **vault-dev:** log init failure detail ([46294dc](https://github.com/bitiq-io/gitops/commit/46294dc7a9b04c9ceff4cac28ebe082e40f09275))
* **vault-dev:** override entrypoint to avoid dev mode ([b749b25](https://github.com/bitiq-io/gitops/commit/b749b25171e26f825d99d6f447a91a9babca5331))
* **vault-dev:** repair bootstrap job recovery flow ([bce624e](https://github.com/bitiq-io/gitops/commit/bce624ef201a464cbe3d26a9a1fb990be9ff3cfc))
* **vault-dev:** run server with explicit config ([46c534c](https://github.com/bitiq-io/gitops/commit/46c534c411485ac85dd2da2dc9347a47c3f173d9))
* **vault-runtime:** template quay dockerconfigjson ([141cdbd](https://github.com/bitiq-io/gitops/commit/141cdbd833a81ee806e88d456d68d4ccbd17327b))

## [0.3.0](https://github.com/bitiq-io/gitops/compare/v0.2.0...v0.3.0) (2025-09-16)


### Features

* **sample-app:** switch to public whoami image; add healthPath support; docs: local runbook notes ([dfce58d](https://github.com/bitiq-io/gitops/commit/dfce58d9f2882e2b006d72bd7afbafa969f00e9b))
* **sample-app:** use public whoami; run on 8080 via args; add healthPath; docs: update local runbook ([92308d1](https://github.com/bitiq-io/gitops/commit/92308d1a001f68c7d9a8361d34c44e1c1bd7d0a9))


### Bug Fixes

* **argocd-apps:** remove goTemplate and use standard placeholders to set destination and parameters ([1c82cfc](https://github.com/bitiq-io/gitops/commit/1c82cfcd05b66857e1de44eb41a1292e9366992b))

## [0.2.0](https://github.com/bitiq-io/gitops/compare/v0.1.0...v0.2.0) (2025-09-10)


### Features

* scaffold GitOps stack (Argo CD + Tekton + sample app) ([f325bdc](https://github.com/bitiq-io/gitops/commit/f325bdc884704d917ba818e82d5dde0bef71b828))
