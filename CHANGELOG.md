# Changelog

## [0.4.0](https://github.com/bitiq-io/gitops/compare/v0.3.0...v0.4.0) (2025-09-19)


### Features

* **charts:** encode composite service matrix in appVersion ([12b8054](https://github.com/bitiq-io/gitops/commit/12b80540f714b8faf16c64f769742079a8e39486))
* **images:** adopt deterministic tag format v&lt;semver&gt;-commit.<shortSHA> ([ac80b84](https://github.com/bitiq-io/gitops/commit/ac80b84f358e06b04bb81b08b6684a6ac65c6566))
* **local-ci:** switch to Quay (toy-service); add Quay secret helper and healthPath override ([#18](https://github.com/bitiq-io/gitops/issues/18)) ([6c7dc94](https://github.com/bitiq-io/gitops/commit/6c7dc946819762a216941921c014c64188efc2f7))
* **local-e2e:** add interactive setup helper ([5695f74](https://github.com/bitiq-io/gitops/commit/5695f7422c0651349181536f9086772697ed5d75))
* **scripts:** add Quay image bump helper and smoke target ([#21](https://github.com/bitiq-io/gitops/issues/21)) ([142a134](https://github.com/bitiq-io/gitops/commit/142a134c9fbb06a96bbba93fd9c1ead57b4e86dd))


### Bug Fixes

* **ci-pipelines:** use artifact hub tasks ([40dbfa5](https://github.com/bitiq-io/gitops/commit/40dbfa5f04420fa5d29b75742886723dbd62e1c4))
* **ci-pipelines:** use artifact hub tasks ([#19](https://github.com/bitiq-io/gitops/issues/19)) ([066b76a](https://github.com/bitiq-io/gitops/commit/066b76a2745bbe8425fe24b48c0ab19423a09062))
* **image-updater:** call run subcommand before flags ([6bb602d](https://github.com/bitiq-io/gitops/commit/6bb602def20aeaca56224efb4926ec9d1a6eac3d))
* **image-updater:** drop unsupported args ([35aecad](https://github.com/bitiq-io/gitops/commit/35aecade214320a356a846f03a1eb90e541b8220))
* **image-updater:** grant cluster access to applications ([b0436c6](https://github.com/bitiq-io/gitops/commit/b0436c6bc96a0aaa5f98d94456644e47e489abbb))
* **image-updater:** grant list/watch on secrets,configmaps in Argo namespace\n\n- Add Role/RoleBinding in openshift-gitops for SA\n- Docs: troubleshooting note about required RBAC\n ([9b23b56](https://github.com/bitiq-io/gitops/commit/9b23b567955db364b01670ea45dd230364f20769))
* **image-updater:** use argocd-server-addr flag ([61bdb0f](https://github.com/bitiq-io/gitops/commit/61bdb0fe93ce019ce49bafa6e878d5796e1f2706))
* **image-updater:** use loglevel flag ([2930dba](https://github.com/bitiq-io/gitops/commit/2930dba7a458cc4891a9a45e220987acff2360f3))
* **pipelines:** align fsGroup with namespace range ([d2aea7a](https://github.com/bitiq-io/gitops/commit/d2aea7a8d2dfc27b66529b62508acf8d62974e2f))
* **pipelines:** allow privileged buildah task ([f3d3b09](https://github.com/bitiq-io/gitops/commit/f3d3b0965e421f78e8f50a3842079ee090655fd8))
* **pipelines:** apply fsGroup via taskRunTemplate ([5292abc](https://github.com/bitiq-io/gitops/commit/5292abcd46b521b6079a511cdb01324c74992c42))
* **pipelines:** bind pipeline sa to pipelines-scc ([0556968](https://github.com/bitiq-io/gitops/commit/05569681ff933d6edff00e8f39461b046c0b158c))
* **pipelines:** ensure Tekton hub tasks run with fsGroup ([b7fbc62](https://github.com/bitiq-io/gitops/commit/b7fbc62cbc2226619dc8af6038cb14be5a60d308))
* **pipelines:** hub resolver tasks + EventListener SA ([#15](https://github.com/bitiq-io/gitops/issues/15)) ([dfc537a](https://github.com/bitiq-io/gitops/commit/dfc537a9f05570e9113ab4a3708c60922c68ed4f))
* **pipelines:** hub resolver tasks + EventListener SA/RBAC; docs for local e2e secrets + webhook; helper target ([#17](https://github.com/bitiq-io/gitops/issues/17)) ([2339429](https://github.com/bitiq-io/gitops/commit/23394296e36e9851589786a1b3c9f4660c1dfdf2))
* **pipelines:** integrate fsGroup podTemplate change ([48286ee](https://github.com/bitiq-io/gitops/commit/48286eea020da2dbf94dd97673fbb035cefd2b86))
* **umbrella:** adopt newest-build update strategy ([31950a7](https://github.com/bitiq-io/gitops/commit/31950a74120616215d19dd96f3e1c31753d067a8))
* **umbrella:** allow image updater to track sha tags ([61f0591](https://github.com/bitiq-io/gitops/commit/61f05913e60cad9fd648c32b69a4fcdf761f9468))
* **umbrella:** allow latest or sha tags for updater ([535266a](https://github.com/bitiq-io/gitops/commit/535266a075a71507d7c80640bd003ce241c8d267))
* **umbrella:** fix image updater write-back path ([5e7e3b8](https://github.com/bitiq-io/gitops/commit/5e7e3b8e54f8c654804a5269549552fe7d9cd02a))
* **umbrella:** pin image updater platform to amd64 ([ee26eca](https://github.com/bitiq-io/gitops/commit/ee26eca1e38371f5139879da6d195fbcbdba16db))
* **umbrella:** point sample app image at toy-service ([44fa576](https://github.com/bitiq-io/gitops/commit/44fa5769ca9f302bbb5fff14c030f2e085379955))
* **umbrella:** rely on default tag policy ([9e1c7c5](https://github.com/bitiq-io/gitops/commit/9e1c7c565df9c7d52a1d33552664330ce776aa89))
* **umbrella:** tighten image updater polling + improve smoke logs ([cd67a81](https://github.com/bitiq-io/gitops/commit/cd67a81bddb7f0290016627d2086cd1892b3cd18))

## [0.3.0](https://github.com/bitiq-io/gitops/compare/v0.2.0...v0.3.0) (2025-09-16)


### Features

* **sample-app:** switch to public whoami image; add healthPath support; docs: local runbook notes ([dfce58d](https://github.com/bitiq-io/gitops/commit/dfce58d9f2882e2b006d72bd7afbafa969f00e9b))
* **sample-app:** use public whoami; run on 8080 via args; add healthPath; docs: update local runbook ([92308d1](https://github.com/bitiq-io/gitops/commit/92308d1a001f68c7d9a8361d34c44e1c1bd7d0a9))


### Bug Fixes

* **argocd-apps:** remove goTemplate and use standard placeholders to set destination and parameters ([1c82cfc](https://github.com/bitiq-io/gitops/commit/1c82cfcd05b66857e1de44eb41a1292e9366992b))

## [0.2.0](https://github.com/bitiq-io/gitops/compare/v0.1.0...v0.2.0) (2025-09-10)


### Features

* scaffold GitOps stack (Argo CD + Tekton + sample app) ([f325bdc](https://github.com/bitiq-io/gitops/commit/f325bdc884704d917ba818e82d5dde0bef71b828))
