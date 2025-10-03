# Changelog

## [0.4.0](https://github.com/bitiq-io/gitops/compare/v0.3.0...v0.4.0) (2025-10-03)


### Features

* **charts:** encode composite service matrix in appVersion ([12b8054](https://github.com/bitiq-io/gitops/commit/12b80540f714b8faf16c64f769742079a8e39486))
* **charts:** prod parity on OCP 4.19 ([#22](https://github.com/bitiq-io/gitops/issues/22)) ([0225f36](https://github.com/bitiq-io/gitops/commit/0225f360487637f496ebf27ea6a7f2c602cdb3d3))
* **charts:** share pipelines eventlistener ([d65336f](https://github.com/bitiq-io/gitops/commit/d65336f3a2007fa470862d97a6c1ff5d3ffa8f4b))
* **charts:** share pipelines eventlistener ([6d2c0aa](https://github.com/bitiq-io/gitops/commit/6d2c0aab77bd79afc055bbf0e2b5687074635795))
* **eso-vault-examples:** support annotations on generated secrets ([8258723](https://github.com/bitiq-io/gitops/commit/8258723c29e41eb89a68b93daacd3f9a70ae0646))
* **images:** adopt deterministic tag format v&lt;semver&gt;-commit.<shortSHA> ([ac80b84](https://github.com/bitiq-io/gitops/commit/ac80b84f358e06b04bb81b08b6684a6ac65c6566))
* **local-ci:** switch to Quay (toy-service); add Quay secret helper and healthPath override ([#18](https://github.com/bitiq-io/gitops/issues/18)) ([6c7dc94](https://github.com/bitiq-io/gitops/commit/6c7dc946819762a216941921c014c64188efc2f7))
* **local-e2e:** add interactive setup helper ([5695f74](https://github.com/bitiq-io/gitops/commit/5695f7422c0651349181536f9086772697ed5d75))
* **scripts:** add platform override to bootstrap ([#31](https://github.com/bitiq-io/gitops/issues/31)) ([04f1858](https://github.com/bitiq-io/gitops/commit/04f1858f312c0e307fc5e7e996bfd7ca6d9054cb))
* **scripts:** add Quay image bump helper and smoke target ([#21](https://github.com/bitiq-io/gitops/issues/21)) ([142a134](https://github.com/bitiq-io/gitops/commit/142a134c9fbb06a96bbba93fd9c1ead57b4e86dd))
* **umbrella,apps:** env-based platform mapping for image-updater ([87fd952](https://github.com/bitiq-io/gitops/commit/87fd9525e35fb963621754272c2638f6ba337c15))


### Bug Fixes

* **apps:** pass platforms field from generator elements to umbrella helm param ([be34538](https://github.com/bitiq-io/gitops/commit/be34538f3c98c39771563547582b0067250b5dc9))
* **charts:** default ENV=local platform to amd64 ([#30](https://github.com/bitiq-io/gitops/issues/30)) ([2c20eca](https://github.com/bitiq-io/gitops/commit/2c20ecaac4a7961b65260cf88537f109516737fe))
* **charts:** manually add old commit for testing ([e722cea](https://github.com/bitiq-io/gitops/commit/e722cea39bff8239cfbb1ac4cb48c020cfd4d022))
* **ci-pipelines:** ensure jsdom env available for jest ([a4dff80](https://github.com/bitiq-io/gitops/commit/a4dff80d8d789e8d78fa6e25b29a68d4f07b5593))
* **ci-pipelines:** handle repos without package-lock ([209faea](https://github.com/bitiq-io/gitops/commit/209faeabd96875e75a4370858f80157f61047896))
* **ci-pipelines:** limit webhooks to push events ([1989638](https://github.com/bitiq-io/gitops/commit/198963887e051cd02b256f6abc42ef8c06735c0e))
* **ci-pipelines:** prefer explicit jest config when present ([6eba95c](https://github.com/bitiq-io/gitops/commit/6eba95c693122bab61736f3ec4aee493a16d61aa))
* **ci-pipelines:** use artifact hub tasks ([40dbfa5](https://github.com/bitiq-io/gitops/commit/40dbfa5f04420fa5d29b75742886723dbd62e1c4))
* **ci-pipelines:** use artifact hub tasks ([#19](https://github.com/bitiq-io/gitops/issues/19)) ([066b76a](https://github.com/bitiq-io/gitops/commit/066b76a2745bbe8425fe24b48c0ab19423a09062))
* **ci-pipelines:** use public node test image ([4ab27b1](https://github.com/bitiq-io/gitops/commit/4ab27b10a4e79ca578740ee060f2247b94203de0))
* **image-updater:** call run subcommand before flags ([6bb602d](https://github.com/bitiq-io/gitops/commit/6bb602def20aeaca56224efb4926ec9d1a6eac3d))
* **image-updater:** drop unsupported args ([35aecad](https://github.com/bitiq-io/gitops/commit/35aecade214320a356a846f03a1eb90e541b8220))
* **image-updater:** grant cluster access to applications ([b0436c6](https://github.com/bitiq-io/gitops/commit/b0436c6bc96a0aaa5f98d94456644e47e489abbb))
* **image-updater:** grant list/watch on secrets,configmaps in Argo namespace\n\n- Add Role/RoleBinding in openshift-gitops for SA\n- Docs: troubleshooting note about required RBAC\n ([9b23b56](https://github.com/bitiq-io/gitops/commit/9b23b567955db364b01670ea45dd230364f20769))
* **image-updater:** use argocd-server-addr flag ([61bdb0f](https://github.com/bitiq-io/gitops/commit/61bdb0fe93ce019ce49bafa6e878d5796e1f2706))
* **image-updater:** use loglevel flag ([2930dba](https://github.com/bitiq-io/gitops/commit/2930dba7a458cc4891a9a45e220987acff2360f3))
* **pipelines:** add logging to compute image tag ([fd549aa](https://github.com/bitiq-io/gitops/commit/fd549aa9ab8e934e88751761f14cc0af2797cc76))
* **pipelines:** align fsGroup with namespace range ([d2aea7a](https://github.com/bitiq-io/gitops/commit/d2aea7a8d2dfc27b66529b62508acf8d62974e2f))
* **pipelines:** align toy-web test command ([94adcb5](https://github.com/bitiq-io/gitops/commit/94adcb58617192063df15c70c6be45b4c92458e5))
* **pipelines:** align toy-web test command ([be5bbf6](https://github.com/bitiq-io/gitops/commit/be5bbf60903c1428161ef29442d457f97bdbd3e2))
* **pipelines:** allow privileged buildah task ([f3d3b09](https://github.com/bitiq-io/gitops/commit/f3d3b0965e421f78e8f50a3842079ee090655fd8))
* **pipelines:** allow tekton git workspace ownership ([de8fa14](https://github.com/bitiq-io/gitops/commit/de8fa14e69f40d384db654c0c2ee553b05e85d22))
* **pipelines:** allow tekton git workspace ownership ([e45fa8f](https://github.com/bitiq-io/gitops/commit/e45fa8fa9ebb6fce36874988b02c011351822776))
* **pipelines:** apply fsGroup via taskRunTemplate ([5292abc](https://github.com/bitiq-io/gitops/commit/5292abcd46b521b6079a511cdb01324c74992c42))
* **pipelines:** bind pipeline sa to pipelines-scc ([0556968](https://github.com/bitiq-io/gitops/commit/05569681ff933d6edff00e8f39461b046c0b158c))
* **pipelines:** ensure Tekton hub tasks run with fsGroup ([b7fbc62](https://github.com/bitiq-io/gitops/commit/b7fbc62cbc2226619dc8af6038cb14be5a60d308))
* **pipelines:** force writable HOME and caches inside steps ([d29bb00](https://github.com/bitiq-io/gitops/commit/d29bb0001c0de53e733b06b5a4fc12a0e129ee82))
* **pipelines:** hub resolver tasks + EventListener SA ([#15](https://github.com/bitiq-io/gitops/issues/15)) ([dfc537a](https://github.com/bitiq-io/gitops/commit/dfc537a9f05570e9113ab4a3708c60922c68ed4f))
* **pipelines:** hub resolver tasks + EventListener SA/RBAC; docs for local e2e secrets + webhook; helper target ([#17](https://github.com/bitiq-io/gitops/issues/17)) ([2339429](https://github.com/bitiq-io/gitops/commit/23394296e36e9851589786a1b3c9f4660c1dfdf2))
* **pipelines:** integrate fsGroup podTemplate change ([48286ee](https://github.com/bitiq-io/gitops/commit/48286eea020da2dbf94dd97673fbb035cefd2b86))
* **pipelines:** robust tag detection ([e3d0d47](https://github.com/bitiq-io/gitops/commit/e3d0d4774523fac843f2d34b6eef4b8fe93d74a4))
* **pipelines:** set HOME for compute-image-tag to avoid /.gitconfig permission error ([aaf92c8](https://github.com/bitiq-io/gitops/commit/aaf92c84eb127164011faed96564d39609cda9b9))
* **pipelines:** set HOME for run-tests to avoid cred copy and cache perms ([32e8845](https://github.com/bitiq-io/gitops/commit/32e88453f05b9f259f9dde30a541fcd487d675fd))
* **pipelines:** set PipelineRun SA to pipeline ([271dac0](https://github.com/bitiq-io/gitops/commit/271dac0619c98c69b0c307b0a313adfc0453f32c))
* **umbrella:** adopt newest-build update strategy ([31950a7](https://github.com/bitiq-io/gitops/commit/31950a74120616215d19dd96f3e1c31753d067a8))
* **umbrella:** allow image updater to track sha tags ([61f0591](https://github.com/bitiq-io/gitops/commit/61f05913e60cad9fd648c32b69a4fcdf761f9468))
* **umbrella:** allow latest or sha tags for updater ([535266a](https://github.com/bitiq-io/gitops/commit/535266a075a71507d7c80640bd003ce241c8d267))
* **umbrella:** fix image updater write-back path ([5e7e3b8](https://github.com/bitiq-io/gitops/commit/5e7e3b8e54f8c654804a5269549552fe7d9cd02a))
* **umbrella:** gate frontend image updates to avoid updater errors in local\n\n- Add imageUpdater.enableFrontend (default true)\n- Disable via ApplicationSet for env=local (enableFrontendImageUpdate=false)\n- Wrap frontend alias/annotations conditionally to prevent "frontend.image.tag parameter not found" and registry unauthorized errors\n- Docs: README + LOCAL-CI-CD note and re-enable instructions ([6f3580a](https://github.com/bitiq-io/gitops/commit/6f3580a4063ac98471ca2084ae34f8f7cf9a6fd3))
* **umbrella:** pin image updater platform to amd64 ([ee26eca](https://github.com/bitiq-io/gitops/commit/ee26eca1e38371f5139879da6d195fbcbdba16db))
* **umbrella:** point sample app image at toy-service ([44fa576](https://github.com/bitiq-io/gitops/commit/44fa5769ca9f302bbb5fff14c030f2e085379955))
* **umbrella:** rely on default tag policy ([9e1c7c5](https://github.com/bitiq-io/gitops/commit/9e1c7c565df9c7d52a1d33552664330ce776aa89))
* **umbrella:** tighten image updater polling + improve smoke logs ([cd67a81](https://github.com/bitiq-io/gitops/commit/cd67a81bddb7f0290016627d2086cd1892b3cd18))
* **umbrella:** use public Go test image ([85d7827](https://github.com/bitiq-io/gitops/commit/85d78271211182c66f99410c55ee424aa8d5343b))

## [0.3.0](https://github.com/bitiq-io/gitops/compare/v0.2.0...v0.3.0) (2025-09-16)


### Features

* **sample-app:** switch to public whoami image; add healthPath support; docs: local runbook notes ([dfce58d](https://github.com/bitiq-io/gitops/commit/dfce58d9f2882e2b006d72bd7afbafa969f00e9b))
* **sample-app:** use public whoami; run on 8080 via args; add healthPath; docs: update local runbook ([92308d1](https://github.com/bitiq-io/gitops/commit/92308d1a001f68c7d9a8361d34c44e1c1bd7d0a9))


### Bug Fixes

* **argocd-apps:** remove goTemplate and use standard placeholders to set destination and parameters ([1c82cfc](https://github.com/bitiq-io/gitops/commit/1c82cfcd05b66857e1de44eb41a1292e9366992b))

## [0.2.0](https://github.com/bitiq-io/gitops/compare/v0.1.0...v0.2.0) (2025-09-10)


### Features

* scaffold GitOps stack (Argo CD + Tekton + sample app) ([f325bdc](https://github.com/bitiq-io/gitops/commit/f325bdc884704d917ba818e82d5dde0bef71b828))
