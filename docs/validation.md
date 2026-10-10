# Validation and evidence

This file holds the tree-bound records that still describe current or published state: the
unpublished release 1.0.7 candidates, the GNOME 51 source evidence, published releases 1.0.6,
1.0.5 and 1.0.4, and the generic evidence layers. Status words are defined in
[Status discipline](#status-discipline). No old report is evidence for the current candidate;
every result belongs only to the inputs it names. The full narrative of superseded 1.0.7
attempts is kept in this pinned commit and in each released tag's own copy of this file:
`git show bfb29bcecfb77fbd5999454f9ed3fe5d899b7202:docs/validation.md`.

## Unpublished release 1.0.7 — current state

Version 1.0.7 is UNPUBLISHED; public latest remains 1.0.6. Work is paused at the owner's request
(2026-10-10) after the Stock failure of child `914ec4d`. Configured release 38079578147 was
cancelled and is terminal CANCELLED. No final-18 asset set, tag, Release, Pages repair or public
VM result exists for 1.0.7, and the workstation was not changed. On resume, investigate phase
`extension-firstlogin-dash` before any new candidate or unchanged retry; graphical recovery and
final documentation reconciliation remain unfulfilled. The resume step is in the [plan](PLAN.md).
Every result below belongs only to the child it names.

### Child 914ec4d (current, paused)

| Binding | Exact value |
| --- | --- |
| Origin main (corrected ambient-root guard) | `5676fd823c819501331a9b5ba5a9d33a0e87e88d` |
| Main CI | 38079280661 / job 114292672389, EXECUTED_PASS, log `90e684616609dcf8494b6ac6e6dab9da1690370423988fa0c29574d6bbcdae9e` |
| Release run | 38079578147, terminal CANCELLED |
| Release child (version 1.0.7) | `914ec4da7251f5605c85114b5765218d64c270ca` |
| Child tree | `004016503726ed4322b5feefcb24880d1092cca4` |
| Child canonical SHA-256 | `87c68f8823de0c5ad757aa49e91781d127c6d6f94078954810ab09464402355c` |
| Source artifact | 11679956373 |
| Source ZIP SHA-256 | `6be351fd01fac766120d2118221cd00f66315e98ebb0729947bafb1a9629c4df` |
| Source bundle SHA-256 | `83f2939caa0643ad11ef6e9fad2d345b0c83f70349c7a475f5d49792e39e34a3` |

| Gate | Job / artifact | Verdict | Key identities and scope |
| --- | --- | --- | --- |
| Source readback and frozen-document review | artifact 11679956373 | EXECUTED_PASS | 224 blobs/modes, 22 deterministic transformations, full 16-file harness, 3 ambient-root guards, exact main provenance, 29-file Markdown inventory; 4 staged source-file hashes unchanged |
| Child source suite and clean build | job 114293582273 | EXECUTED_PASS | full namespace 10 / signer 14+18 / deferred none, 7-package verification; log `3d31e5ab99d43ad43760c7dbb4ebe26c1125e6189e8a0804afcc52fdf8f76389` |
| Unsigned readback | artifact 11679757321; CI readback job 114294713131 | EXECUTED_PASS | 7 packages against 64 immutable inputs and 42193 mtree rows; ZIP `de2703d7a1746033fb72aa9ef7c75b8307bf15ba78fe32e90df1575e10ec077c`; BUILD-METADATA `a11ce8fc288cf96db0a1ce91387a5cbe064a01ac87c814d5a032250aa7a1aafb`; UNSIGNED-SHA256SUMS `8776c0162bbc9ea1cc03611cb25bc97604f4a476f48e48eda6de7a842d9555cb`; CI log `238cb88ad14712438e80c2f8a575616535c0c70efb10f9adc35be5b1d136e671` |
| Root gates and signed Phase-A | snapshot job 114294899009; artifact 11680745322 | EXECUTED_PASS | job log `e31e584db31be8a732dce17fa01109e836272a016bfbe64ec7ff02040b0c6f77`; both repository modes full 10 / signer 14+18 / deferred none; sealed root publication (4 namespaces, PID1, agent, supervisor); ordinary keyring 5 (privileged deferral), privileged keyring 10 / deferred none; ZIP `f6a421226561eb4752f0f7e3f42e917c575e144c2d9464e91a1146e3edf36afb`; RELEASE-SHA256SUMS `ff29609af5fcc425e685315165a559ffd04eb2c3d9c7e88f421f2ab8d505ad91`; signed archive `fd06f9da679218d3579821c1a8cfaaacefece98f6672eb4359a4e08f63645ef6` |
| Minimal TTY / ext4 / systemd-boot | job 114295787555; artifact 11680118942 | EXECUTED_PASS (14 assertions) | run `minimal-20261010T193850Z-c13843f0`; ZIP `0e13a5c55916b24c481bdd69eeffc6af33893ebd5ffa89fbc4a9f5e6299b2803`; archive `95e0fc2b1a81b6d1839b689be96c20ddc4c329f833a7de2c68756bbd52b534e6`; result `bab0b7edc9af3927cdbb9b944dbbe54033d357509170add6ee4cf1137c7ad346`; strict consumer `7f38f4ef52dff1bc569361c65b2f9ca5d88af21e095f9c210e8099f3f7aeabc6`; log `a7c1634eb5edc33205928652156707f0bcf8ef95021b430f484b25d33af545df` |
| Stock GNOME / Btrfs / LUKS2 / GRUB | job 114295787485; artifact 11681356004 | EXECUTED_FAIL | run `luksgrub-20261010T195149Z-d6e6af82`; phase `extension-firstlogin-dash`; cause NOT_PROVEN; ZIP `e4c534bf09949ad6a209e0a7266ea0f9c0a519df71a46364bf1171ee1eb01399`; evidence `a721ec7cd1e17c978d937eef7c7bf57cfa8c3c86d84bde68de18f9e0c8102ecc`; result `de41e10ea3b9f4bdf389be164003e5d389da2162f1013d52836fbbdd863989ee`; log `4f9d1ec64378cf1e6797e885d85e7328ff2cdee60ca2b06eaf2ed012547bbeb8` |
| Marble (core) | job 114295787533 | CANCELLED, no verdict | stopped during input preparation, before any guest verdict; cleanup 20:10:31Z, log `f4698c186bfcda947aa31aff88b9674f17cab44c76d864727b81f8a3dede5867` |
| Six supplemental scenarios | not run | CANCELLED, NOT_TESTED | no artifacts |
| Finalization, tag, Release, Pages, public VM | not run | NOT_TESTED | no final-18 or public acceptance |

Root gates, Phase-A readback and signing details. The snapshot job's fixture-14/18 receipts are
not production final-18 acceptance; actual signing produced the exact Phase-A 14. Root and a
separate read-only review verified exact 14 files / 12 manifest rows / 25 covered snapshot
objects, 3 outer and 10 inner signatures against the exact child trust, all 7 signed package bytes
equal to the accepted unsigned bytes, payload/SRCINFO and database/file-list semantics and signed
aliases. Root ran the child `repository/verify-database-metadata.py` against 65 immutable source
inputs; two diagnostic invocation errors (full paths instead of basenames; an archive reader that
omitted 2 directory entries from 29 members / 27 files) were corrected without any product-input
change and are diagnostic-tool failures, not product failures. A peer verified all 37 staged file
hashes unchanged.

Stock failure detail. Fifteen assertions preceded the failure, including real GDM password and
Wayland login and 7/7 enabled extensions; preparation completed successfully at 20:07:29Z (the
earlier ambient-root preparation failure is resolved). The last begun phase is
`extension-firstlogin-dash` at 20:07:29Z; the terminal result records `failedPhase=firstboot`,
exit 1. No extension functional PASS and no underlying cause is established, and the retained
compact evidence does not identify the detailed failure. The failure-only artifact binding
verified exact source, tree, full 16-file harness and inputs; it deliberately does not run the
strict PASS consumer or convert the 15 intermediate rows into acceptance. Stock job cleanup
completed 20:08:08Z. A source-bound runner-host inotify observer captured preparation stderr with
no allowlisted Python exception, filename, line or status matches; that is successful preparation
stderr, not evidence of the failure. It exited normally (owned PID 3395998 verified absent by
strict SSH); no raw private stderr persisted and no guest, session or configuration action was
performed.

Owner pause and cleanup. The owner asked to complete the current result and pause. Root verified
run 38079578147 / head `5676fd8` and requested cancellation; the run is terminal CANCELLED.
Read-only runner checks verified no owned Minimal/Stock QEMU PID or run directory, no old Stock
firstboot PID 3403414 and no observer PID 3395998. The canonical plan holds the resume step; only
PLAN and validation checkpoint files were dirty and the index was clear.

Advisory observation (not source-pin promotion, VM or public acceptance). `python3
maintenance/check-sources.py --network --report REPORT` completed at 2026-10-10T19:41:36Z with 40
observations, advisory drift and no query errors. Shell 1:51.0-1, GDM 51.0-1, GTK4 1:4.24.1-1 and
libadwaita 1:1.10.0-1 match the candidate platform observations. Official AUR HEADs: Plymouth
`3347bb2b0ace31f6fa07e080f2886cd04e3fea1d`, Bibata `5d418e2c328f988b0b5c4fc51e6ca9619bfda293`
(equal to the official Arch GitHub mirror branches). Manifest SHA-256
`c146c1234307d6b616a356c0abfafaee195bcfc66dbee8daabda12c1024b5353`; report SHA-256
`1e0b69eee9ca0625538637c00913e8d3c0f91a107de63e72f642b95799fc73fa`. A separate isolated
unprivileged `git clone --no-checkout` of both primary URLs matched the installer pins by retained
commit and `git archive` SHA-256: Plymouth
`508d4c782543fa72a01284c28f43db55819bab23f7915eb3abae2beb2fb4d9c9`, Bibata
`887ea3300b82fd7fd8a46617fd00dc9e596daa99e7865c7353cb7d8073b6e2b4`. No recipe was executed, no pin
or host setting advanced, and immutable legacy AUR inputs remain unchanged.

### Previous child 106dcc0 (superseded)

Release 38073967896 prepared child `106dcc01bfa485745eb950624e25698877c63328` (version 1.0.7),
tree `9fe0a590063b1e089b58ed10c6394a1e74d66a36`, canonical SHA-256
`64780ee38132255be1a0b442cd0c351dceb7daa1284ab75dd25a64a9d224673e`, from origin main
`afefc9885aa3f4bae0b39c8679068adadab53e7d` (tree `c84ba158534e11b760e398059e72258fb0b501b5`,
canonical `cdaeffbe66419d7988994ed49a586074eccd0772229590082e0687ec89e3e6b8`). That main is the
squash of PR90 (head `ca70a7e6dec382dd3be7a005647f3baaedfebbab`, same tree/canonical), which added
the deterministic historical source-freeze qualification of the child PLAN/validation snapshot.
PR90 CI 38073292610 / job 114274961921 PASSED (log
`5658ba8ede3f3e00533a71979d7ec179e3ac27d638087397e20a04f8423e491f`); main CI 38073664462 / job
114276054348 PASSED (log `2ff6623938958548fe15f2dd96800d91a942649185e2f17b4e726213cc6fc99d`); the
clean exact-candidate suite log is
`4e7a13868c9c654df7141d3c8eea2081528d245e45b818e4195509b9ee59fecf`.

| Gate | Job / artifact | Verdict | Key identities |
| --- | --- | --- | --- |
| Source readback | prepare job 114276957728; artifact 11678291477 | EXECUTED_PASS | ZIP `894fa4791335abd89f7858c5ee2ace2cdf925d4e76594fab0e2509989d5744a9`; bundle `967c0e622853962526b8dee16a78f87ca1e1c7ff48161fea09c640ed5a207655`; 224 blobs/modes, 22 transformations, full 16-file harness |
| Child source suite and build | job 114277010196 | EXECUTED_PASS | log `3fd8da0d8a109a91c3acd2a8ba02b5c217c55a03abdcc13151d4580ee77f0034` |
| Unsigned readback | artifact 11678022359; CI job 114278244198 | EXECUTED_PASS | ZIP `9fdd4f9b374b3652e7788c348d025b787737843303fa030c21fa1e2395d8e136`; BUILD-METADATA `f7e51dcd0bc2abfa5e9ad955a135389330efa5452ed53d85541c4b866241d6f0`; UNSIGNED-SHA256SUMS `1ed7d51fd20d140ca3b14b89f1cb4e466894f0b50ffe74d210fd022b0c34cd97`; 7 packages, 64 inputs, 42193 mtree rows; CI log `5ce5d6b19fd8edb0ef12ff04f36a86f5d18ad1dac1bb77ad405aa79b6e5eb911` |
| Root gates and signed Phase-A | snapshot job 114278477881; artifact 11678127883 | EXECUTED_PASS | log `01be121aa3c593d21358e5c03b22910ec2af8a4745fddc74ce8ee08f849a80f3`; ZIP `d37125b89f2f2b4736d931f304eeef059fac616508219c7b2b735da4f7521014`; RELEASE-SHA256SUMS `7a2dbb906e901a49609e6011c0d272447b10a98d151fab633d7d04bda78ae7f4`; signed archive `cb07dcbc52d6043c13c9cf8daa2cf9b5bb51276c374bfc6435b1aedee7fe5616`; 14 / 12 / 25, 3 outer + 10 inner signatures, 37 staged hashes unchanged |
| Minimal TTY / ext4 / systemd-boot | job 114279194036; artifact 11678114269 | EXECUTED_PASS (14) | run `minimal-20261010T181341Z-d4568747`; ZIP `1f12a17365020073d5ee9ac647d076c541801591c56897960200b8db72f30e58`; archive `183eb6a7d2a1f38afd4b28f4228c1cac9b11b90510ce7807d2b6ba5dc37c4c33`; result `28f42cc03d2e3de6b9b28b8ebee2e233335f27d1eae03114819daee6aa137305`; consumer `7f38f4ef52dff1bc569361c65b2f9ca5d88af21e095f9c210e8099f3f7aeabc6`; log `32ed942ffc44762cdc90c645b27172fed006ac465e6cf4772dd903d425775a84` |
| Stock GNOME / Btrfs / LUKS2 / GRUB | job 114279194093; artifact 11679506208 | EXECUTED_FAIL | phase `extension-firstlogin-prepare`, run `luksgrub-20261010T182755Z-de1189c7`, failed 18:42:40Z; job log `73a83d0611119d8f8165cfe228bb59476ef6e0435f71d5e6c28983fa284d4ea9`; ZIP `8a2be832b9382c75ff88b98cbe426556e89a0377c8e328f5455e0d4f7424e042`; evidence `d53daffca924999f1ffe3a9c0e860fde0e5abb1c3bbd5017a0848e9c1d43f299`; result `14121971e7948ffd8de8ab5dabbf04df53c5dc267602ead3e2be51b1cca453d1` |
| Marble (core) | job 114279194053 | CANCELLED, no verdict | run `marble-20261010T184901Z-ec8a96f1`, stopped at installer completion (exit 130) |
| Six supplemental scenarios | jobs 114279194055, 114279194071, 114279194099, 114279194128, 114279194133, 114279194586 | CANCELLED, NOT_TESTED | queued, never ran |

Stock failure. The 15 preceding assertions include real password login and 7/7 enabled extensions,
but no functional test passed. Sanitized evidence records guest script-error line 4522 / status 1;
raw stderr was already removed by owned job cleanup, and the earlier large-argv failure did not
recur. Read-only diagnosis then bound the Marble run to its actual mounted Btrfs target `/mnt`
(UID 0, inode 256, device 73), whose mode was 0755 at 18:54:10Z and 0555 at 18:55:12Z while
`/mnt/usr` stayed 0755 (frozen QGA client SHA-256
`93e7ccdc4600fb42fdf5883ac7e93cfc62ae41a0d0c260a7b67a4e54aae8c288`). The Arch ISO `/` is
separately 0555 on overlay, and the workstation `/` is root-owned 0555 Btrfs with `/run` 0755. The
exact helper's finite fixture reproduces 0755 PASS versus secure 0555 ancestor rejection at the
all-ancestors exact-mode assertion. That guard defect is confirmed independently; it does not
supply the pruned Stock traceback or establish its particular Python assertion.

Cancellation. Unchanged release 38073967896 could not be accepted after Stock's mandatory failure.
The source-bound read-only observer (PID 3134793) was stopped through a retained pidfd and
confirmed absent; the last 19:11:41Z mounted target-root stat was 0555. Root then cancelled the
run through the Actions API; run and job metadata ended CANCELLED, Marble stopped at 19:12:57Z /
exit 130 (an interruption, not a Marble product verdict) and all 6 queued scenarios were
cancelled. Terminal log `8143686ecd68445d1e2cff70fa402716b0555eb81cbedeb2d21ad44e17732942` records
job cleanup complete at 19:12:59Z; a later strict-SSH read-only query confirmed the old QEMU
process and run directory absent. No tag, final-18 or public delivery was accepted.

### Ambient-root correction (118b181, PR91, main 5676fd8)

The actual GTK-code helper rejected a secure 0555 ambient ancestor before the fix while the 0755
control passed (RED). The focused change in `tests/vm/guest/verify.sh` keeps all three owned code
directories exact 0755 and limits ambient directories to root-owned 0555 or 0755; preparation
creates only owned directories, and receipt validation and cleanup apply the same distinction.
Original/source 500 and code 555, hashes, no-follow, links, retained descriptors, inode and
live-process proof remain. `python3 tests/vm/runtime-checks.py` returned EXECUTED_PASS, 176 tests
in 33.148s; the two actual-helper/native tests passed preparation, live receipt and cleanup at
secure 0555 while invalid owned/ambient modes and symlink replacements were rejected. An
independent read-only review found no material issue; Bash syntax, ShellCheck and diff checks
passed. Precommit `umask 022; PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` returned
EXECUTED_PASS (log `4438c0dd86722c705c207cfd7154e196bb3dbfc734a9c60e5e1ed936d2d216b8`).

| Delivery step | Exact identity |
| --- | --- |
| Clean exact candidate (PR91 head) | commit `118b181c8fac3e20ef86366424f7509dfdfb35f0`, tree `fbbee6958efecae9fd889314638626452f3d34db`, canonical `c2eb812f9d0ff48d9ee278f85ece9cb052819d71a3d133aff0ce6e45103a5d5c` |
| Clean source suite (EXECUTED_PASS) | log `8e5e0f29aa61963332c6e3f90c277d304493216c6d9cac40047072314aade17d` |
| PR91 exact-head CI | 38078747603 / job 114291101113, EXECUTED_PASS, log `d573257b535d4066a119a827abe9ea1b21e77275397f33e16e70ed7eec477ec1` |
| Protected squash merge, 19:18:32Z | main `5676fd823c819501331a9b5ba5a9d33a0e87e88d` over base `afefc98`, same tree and canonical hash |
| Main CI | 38079280661 / job 114292672389, EXECUTED_PASS, log `90e684616609dcf8494b6ac6e6dab9da1690370423988fa0c29574d6bbcdae9e` |

The same-checkout main fast-forward preserved both dirty documents byte for byte and the clear
index. No release, VM or public result transfers from the PR; the corrected child is `914ec4d`.

## 1.0.7 attempt history

One row per configured release run for 1.0.7, in chronological order. Dates are UTC dates taken
from recorded run or scenario timestamps; rows 1-5 predate 2026-10-09T05:31Z and carry no exact
timestamp. "Main" is the reviewed origin main that produced the child; the correction column names
the protected PR and resulting main that the next row builds on. Per-attempt hashes, artifact IDs
and step-by-step receipts are in the pinned commit named above. No row transfers a verdict to
another child. Verdict classes: FAIL = executed failure; CANCELLED = run stopped by root or
timeout before completion (interrupted scenarios are NOT_TESTED, never relabelled FAIL).

| # | Date | Release run | Child (main) | Furthest stage | Verdict | Cause class and cause | Correction |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1 | <=10-09 | 37879163690 | `5ee1439` (`63c9e6c`, PR65) | build PASS; protected readback | FAIL | source guard: public trust certificate in checkout was group/other writable | PR66 protected readback correction |
| 2 | <=10-09 | 37880984567 | `3c3b237` (`aa462e1`) | build PASS; protected readback (source PASS, unsigned-package mode guard) | FAIL | source guard: artifact-extracted package modes rejected | PR67 artifact normalization, checker-clone umask |
| 3 | <=10-09 | 37882590902 | `dc01f6e` (`3e0a57f`) | readback PASS; snapshot gate, full repository modes and publication root PASS | FAIL | test harness race: ordinary keyring cleanup lost a GPG socket between enumeration and deletion; privileged keyring and signing skipped | keyring-fixture cleanup correction, 25 regressions (candidate `b819ab9`); PR number not recorded |
| 4 | <=10-09 | 37884673557 | `9143b77` (`7203ec6`) | child source suite PASS; build | FAIL | external download: pinned Dash to Dock archive, curl 35 TLS EOF | none (source unchanged) |
| 5 | <=10-09 | 37885316974 | `9143b77` (`7203ec6`) | build | FAIL | external download: same pin, HTTP 503 on all 4 attempts (upstream application unavailable) | none; same-input retry after upstream recovery |
| 6 | 10-09 | 37888302371 | `9143b77` (`7203ec6`) | all gates through Phase-A signing; Minimal PASS (14); Stock interrupted | CANCELLED | harness integration: consumer `HARNESS_FILES` order differed from producer (`QEMU harness manifest row differs`) | PR69 consumer tuple reorder and actual-producer regression |
| 7 | 10-09 | 37890827364 | `5d291a9` (`4924cb8`) | Phase-A signed; Minimal PASS (14); consumer accepted real evidence | CANCELLED | documentation: contradictory installation recommendation in frozen docs (cancelled before publication) | PR70 |
| 8 | 10-09 | 37893328836 | `c5d6553` (`85e12ab`) | Phase-A signed; Minimal PASS (14) | CANCELLED | harness: Stock and supplemental Stock `install-archiso` bootstrap deadline (no console-readiness gate); Marble pre-VM `/usr/bin/python` absent on the Ubuntu runner (exit 127) | PR71 readiness/HMP helpers and separate pinned Arch verifier (main `4c50728`) |
| 9 | 10-09 | 37899808850 | `018ef17` (`4c50728`) | Phase-A signed; Minimal PASS (14); Stock, Marble and 4 supplemental installers exit 1 | CANCELLED | installer / external transport: AUR TLS EOF for Plymouth and Bibata with no fallback (established for the encrypted Stock run; others unclassified) | PR72 official Arch mirror fallback after failed AUR clone, ERR-trap line fix (main `168f3eb`) |
| 10 | 10-09 | 37909100627 | `8ad8ef1` (`168f3eb`) | Phase-A signed; Minimal PASS (14); Stock `install-archiso` | CANCELLED | installer defect: mirror directory name rejected by `aur_package_output_path_is_safe` | PR73 predicate-compatible name (main `cadd63d`) |
| 11 | 10-09 | 37914520768 | `35ff8df` (`cadd63d`) | Phase-A signed; Minimal PASS (14); Stock runtime PASS (22) but strict consumer rejected; Marble `legacy-login` | CANCELLED | (a) consumer: Stock `repository-runtime.sha256` and port row restricted to Marble; (b) harness: legacy GTK equality asserted on GNOME 51 | PR74 consumer and session-predicate corrections (main `b10e115`) |
| 12 | 10-09 | 37921973159 | `a35fa3e` (`b10e115`) | Minimal and 7 other scenarios PASS; core Marble bootstrap readiness FAIL (cause unproven), job rerun failed `gnome51-baseline-install` after 7 assertions | FAIL | harness: staged guest lacked test-only `jq`; failed producer hidden by process substitution | PR75 provision `jq`, checked producers (main `322e331`) |
| 13 | 10-09 | 37943281539 | `cd43614` (`322e331`) | Minimal PASS; Stock FAIL (`unlock`, `LockedHint`); Marble FAIL (`gnome51-upgrade`); ext4 PASS | CANCELLED | harness: test HTTPS server honoured If-Modified-Since / Last-Modified, so plain `pacman -Syu` got HTTP 304 and a mismatched signature pair (reproduced); Stock unlock cause unproven | PR76 server correction (main `0d6b246`) |
| 14 | 10-09 | 37955123850 | `00d97e3` (`0d6b246`) | Minimal, Stock (22), ext4 PASS; Marble `return-user-login` | CANCELLED | diagnostic: observer queried the wrong Shell unit; disabled-extension cause unproven | PR77 `@user` observer with event timeline (main `30ebf25`) |
| 15 | 10-09 | 37967163595 | `a7730dd` (`30ebf25`) | Minimal, Stock PASS; Marble pre-VM FAIL; ext4 FAIL | CANCELLED | (a) external: accepted ISO transfer, curl 56 TLS EOF; (b) harness: `gnome-extensions list` queried before readiness poll (status 2) | PR78 poll ordering (main `65f6713`) |
| 16 | 10-09 | 37978505750 | `1274611` (`65f6713`) | Minimal, Stock, ext4 PASS; Marble `return-user-login` | CANCELLED | diagnostic: broad journal window rejected (129 records without MESSAGE_ID); TLS fixture port-publication race; Marble recovery cause open. Main CI of the correction hung on an archive-verifier `SIGALRM` / wait-lock race (reproduced, cancelled) | PR79 filtered lifecycle query and atomic port publication (main `69377c3`); PR80 alarm-mask fix (main `6ef601b`) |
| 17 | 10-09 | 37993529797 | `a5cb4b5` (`6ef601b`) | Minimal, Stock, ext4 PASS; Marble `extension-upgrade-dash` | CANCELLED | NOT_PROVEN: Shell SIGSEGV during logout observed; Dash launch left no receipt | PR81 probe observations and stack-module attribution (main `2414cef`) |
| 18 | 10-09/10 | 38002781657 | `a5e4197` (`2414cef`) | Phase-A signed; Minimal job stalled until job-limit cancel (no artifact); Marble, Stock, ext4 FAIL | CANCELLED | NOT_PROVEN: Marble named-user session wait (Shell killed by signal 9); Stock `LockedHint=no` after password input; no phase evidence | PR82 phase observations, PAM diagnostics, `qga_verify` returns (main `1e9c33d`) |
| 19 | 10-10 | 38034970799 | `f62fcfb` (`1e9c33d`) | Phase-A signed; Minimal FAIL at firstboot after 3 assertions; Stock interrupted | CANCELLED | harness ordering: `systemctl is-active NetworkManager` (status 3) ran before the `nm-online` wait | PR83 reorder, signal traps, progress notices (main `e4c96c0`) |
| 20 | 10-10 | 38042159246 | `912cfae` (`e4c96c0`) | Phase-A signed; Minimal PASS (14) | CANCELLED | documentation: stale README limitation in the frozen child (cancelled by root before publication) | PR84 (main `289fda5`) |
| 21 | 10-10 | 38044528734 | `2e54849` (`289fda5`) | unsigned readback PASS; cancelled before signing | CANCELLED | documentation: `release-process.md` heading called dated 1.0.6 evidence the latest delivered release | PR85 (main `09e3044`) |
| 22 | 10-10 | 38045648678 | `daec8e9` (`09e3044`) | Phase-A signed; Minimal, Stock (22) PASS; Marble `fresh-user-login` | CANCELLED | NOT_PROVEN: authentication failure for the fresh account without PAM session-opened; audit found no functional checks for several extensions and none in Stock | PR86 native extension observers, 16-file harness (main `c9ea039`) |
| 23 | 10-10 | 38059360429 | `43410ed` (`c9ea039`) | build and unsigned readback PASS; root-gate job | FAIL | source-gate fixture: publication-root fixture lacked the new native harness files (before signing) | PR87 fixture closure and receipts (main `a9831fa`) |
| 24 | 10-10 | 38061649342 | `a6887ee` (`a9831fa`) | Phase-A signed; Minimal started | CANCELLED | test-tool defect: GTK probe user-owned code path could be substituted and still pass receipt validation | PR88 root-owned 0555 code path (main `057f606`) |
| 25 | 10-10 | 38064355933 | `fd91397` (`057f606`) | Phase-A signed; Minimal PASS (14); Stock FAIL after 15 assertions | CANCELLED | harness transport: `jq --arg` payload of 138416 bytes exceeded the 131072-byte per-argument limit | PR89 stream via `jq --rawfile` (main `4eadf74`) |
| 26 | 10-10 | 38072414609 | `c7caf7a` (`4eadf74`) | source readback; build in progress | CANCELLED | documentation: frozen PLAN claimed 1.0.7 UNPUBLISHED / pending for an older attempt without historical scope | PR90 source-freeze qualification (main `afefc98`) |
| 27 | 10-10 | 38073967896 | `106dcc0` (`afefc98`) | Phase-A signed; Minimal PASS (14); Stock FAIL `extension-firstlogin-prepare` | CANCELLED | harness guard defect: secure ambient 0555 root ancestor rejected by exact-0755 assertion (confirmed) | PR91 ambient-root correction (`118b181`, main `5676fd8`) |
| 28 | 10-10 | 38079578147 | `914ec4d` (`5676fd8`) | Phase-A signed; Minimal PASS (14); Stock FAIL `extension-firstlogin-dash` | CANCELLED (owner pause) | NOT_PROVEN: failing phase begun, no detailed cause retained | none yet; see current state |

Source-side events outside a release row: the main CI after PR79 (37988828109, job 114017496279)
was cancelled after the archive-verifier deadlock was reproduced (fixed by PR80, whose main CI
37993132347 passed); the main CI 38070409148 of PR89 queued about 25 minutes on the dedicated
runner with no proven cause and then passed without a restart or configuration change.

## GNOME 51 candidate — 2026-10-09

This section records the initial source, native and unsigned checks that preceded the prepared
1.0.7 children. At that stage no new release, signed package update, real GDM or upgrade VM, or
public pacman delivery had been accepted; later children are recorded above with their own
identities, and the [active plan](PLAN.md#gnome-51-update-recovery--2026-10-09) holds current
delivery status. Historical release 1.0.6 evidence is unchanged.

Scoped native checks used installed Shell/Mutter/GDM 51.0, GTK 4.24.1 and libadwaita 1.10.0. The
existing Shell and GTK stylesheets parsed. An isolated DynamicUser headless Wayland session loaded
eight Marble extensions with enabled state 1 and empty extension errors. Shell's diagnostic Eval
interface rejected functional exercises, so menu, clipboard and screenshot behavior, visual
appearance, password login, lock/unlock and real package migration are NOT_TESTED by that smoke
check. Owned transient units, processes and input fixtures were removed.

Native disposable package builds of the final extension bundle, profile and dual GDM payload
passed the production archive verifier. A private installed-database copy resolved the proposed
profile and bundle upgrade with `pacman --print -Su` without installing anything. The legacy GTK3
VM scenario does not create the old four AUR extension owners or the user-local No Screenshot Box
tree, so it cannot establish the new upgrade's acceptance; the source candidate therefore added a
separate mandatory staged 1.0.6-to-GNOME-51 migration (actual AUR build inputs, independent
manifest digest, password logins, preference/custody checks and exact replacement through `pacman
-Syu`). Source regressions are not VM results, and the eight-extension enabled-state check is not
behavioral extension acceptance.

| Executed check | Commit / tree | Result and log SHA-256 |
| --- | --- | --- |
| Clean Arch build: `repository/build-packages.sh` and `repository/verify-unsigned-build.sh` (7 packages; pinned image `sha256:714acd1eef9ae997d95691b1c5220ada0076185b77857c1813f02de0fa83cf7b`, non-root builder, read-only source) | `6b13bbd993faca85fcdd20e40d8ae3993443182d` / `275464258dd8d4663c5d1265a91b991b18b7aa53` | PASS; build metadata `8ba8ccf2619870623798263568304815513b11b1fa71688bb75484b3d7a13ac0`; unsigned manifest `28f66a4bf871c29379354190ce37849fa9274a27129b556fcc12ac940f925f0b`; log `416c5b2e37e9c7871afd006baef522090340b5da59ceb253343b9c0b28facb7f` |
| `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` | `d81f0a07a5962e47317251745789ddc3b727e75d` / `f3d7f15e26f80ddcc2a590224fccf011d8b37540` | PASS; `296434ddd3e019d9594bcfd1843f58bb07fbf803feed35de2a01f74bd07bfcae` |
| Exact empty-environment root publication check from AGENTS.md | same | PASS, exact 14/18 closures, four namespaces, supervisor-death cleanup, no deferrals; `07dba168db2f1564cb18cc4e014d1b18d8215cf876b5a2e37a49a3a8ef86f644` |
| Ordinary `bash tests/keyring-rotation-checks.sh` | same | PASS; `fe74de28be8117dfe6234912abb3b070041be1080d16e6aad4f41d3618fe4d45` |
| `env ARCH_LINUX_PRIVILEGED_ACCEPTANCE=true bash tests/keyring-rotation-checks.sh` | same | PASS, full namespaces, ten scenarios, signer passed, no deferrals; `4129134eac1c23c902481e0788166ee76242817b9fc4534f1355754e48821281` |
| Full source suite on functional candidate (126 runtime fixtures, 7 functional-evidence checks, 33-assertion Marble contract, full namespaces) | `a1a3d2683de1f21fa3fcd3f926b901b087bae908` / `ecbf5bd73e547338f4639c37ec9d1ef0e27a6983` | PASS; `7f1c29d8bc24346e1ac969a5812e8dda8470ca6a25f2092effbb22586370ca1c` |
| Exact root publication command (6 behavior-receipt requirements, full 14/18) | same | PASS; `1561bc69968f00829813e9c1d6253cb264c4535717d57ce36aac5ccc51cb61ea` |
| Full source suite after the final legacy-input fixes (17 upgrade-input regressions, 126 runtime fixtures, 29-page docs/link checks, ShellCheck) | `c5a2b8f77947b6a146eebef6808141971e363283` / `4b644f379744507178d2f8dc85c947dc64a84533` | PASS, exit 0; `3d4822005934279fe6e625c23554633663bd7743cce851ed5ac8f6978e90614a` |

The first row is a raw-source package-revision receipt only; it does not establish the future
release child's upgrade revisions, production signing, real package migration, GDM acceptance or
public delivery. The root checks used disposable fixture keys, a pinned Arch container with
private tmpfs test directories (earlier overlayfs attempts rejected directory link counts before
private signing access; no production check was weakened) and an owned loop-backed disk; all
containers, loops, mapper and child cgroups were removed and host device metadata was unchanged.
They do not establish production signing, and later harness changes do not inherit these receipts.
The checkout remained clean.

Authentic legacy upgrade-input preparation passed on clean commit
`7a61c40fd42087928e1a2611d02f3ed059dbbfc1`, tree `ea4367c55601b3c4c920759e5ecf90468e519613`, with
`python3 tests/vm/prepare-gnome51-upgrade-inputs.py --source-root "$PWD" --output "$INPUT_DIR"`
(absent output directory, pinned disposable Arch builder). Independent worker and root calls to
`verify_inputs(source_root, input_dir, expected_manifest_sha256)` both passed with the manifest
digest supplied separately; the closure also holds the ten pinned release 1.0.6 assets, and the
production archive and metadata checks verify all four packages (Dash epoch, sole Clipboard
conflict from its hash-bound `.SRCINFO`).

| Legacy-input binding | SHA-256 |
| --- | --- |
| Canonical manifest, exact 15 payloads | `4df9dfb4bb0089d4dca0db10c75173e414d417f38d6d6ad013a0b3f1320a4972` |
| Blur my Shell 72-1 archive | `1ed802469128a4b5c88c60c6a4c4109fc30499d2f3814abb6eeb338da5f4e164` |
| Clipboard Indicator 71-1 archive | `ccefdda5329aee53fa73d441adef92be5539e61b87f6c950265d9d2499a493c2` |
| Dash to Dock 1:106-1 archive | `8c0a05c958ec098ecc40a9e43876d89bb9df21a084a2f9e9b421417189e6523e` |
| Just Perfection 37-1 archive | `8bc46a4d26fe068adaa9dd046331d92269d5787267e9ad32434f12473d9dbc6d` |
| Original local No Screenshot Box archive | `6b1c5184579ca03dc9bf0ad6ded39d99e618c8baf4577ff5391cfa185eb0736e` |
| Preparation log | `28f34f07f25f22bf3c16c3fd543933ab5b113c1f9fed1b2a864fd1086bccd048` |

This is input preparation, not an installed upgrade or a GNOME behavior PASS, and it does not
transfer to any later release child's different source identity.

## Verified release 1.0.6 — 2026-10-04

[Configured run37214392242](https://github.com/snaplyze/arch-linux/actions/runs/37214392242)
produced [immutable release1.0.6](https://github.com/snaplyze/arch-linux/releases/tag/1.0.6),
Release ID403102824, published2026-10-04T16:22:59Z with exactly18 assets after verified Pages deployment.
[PR59](https://github.com/snaplyze/arch-linux/pull/59) passed required Source checks before squash;
this same checkout returned to main by fast-forward. The candidate and originmain share exact
mode-and-byte source identity; the version-only release child is bound separately.

| Binding | Exact value |
| --- | --- |
| Pre-merge accepted candidate | `a9e417304e9883aa354f5ed2cda6a9ead0438eec` |
| Origin main | `696b420bc93415d44bb3ab64b35df7539cbbe87b` |
| Origin/candidate tree | `2d3e7f1abf454c462586cb5450ae1c79d3ccee0a` |
| Origin/candidate canonical SHA-256 | `6d8da82f8008f9d8d002f8a9bd0bb3c60b7db6530eb4894657ad0fcfd38d6250` |
| Release child | `7af2209be497a0a5f0e314cd8cc20f691e52b064` |
| Release tree | `83bd2d9de7d4883b08fbb81c78cce8fe0d36374d` |
| Release canonical SHA-256 | `f6b6517655429ca06afb1cd241d971fe4ccb02352a231020145853ed8b7185ff` |
| Annotated tag object | `54d1208417e872bb08b5b9128752d36030205145` |
| Accepted October ISO SHA-256 | `684ded26c63240ff4a41e8c25ee84ea6da233f557364821f13d12c2b0a9059a5` |
| Repository snapshot SHA-256 | `25a129f7fa0f91d9ec85d0418ba938dd62e7fea0052838f76b89b3292a795496` |
| Build metadata SHA-256 | `b8cbf4689bac5ad75403a5fc2a1f17e8415a706b5c076d84bb2511e0dfecefec` |
| Unsigned manifest SHA-256 | `b5115ae0838e9c5f01a7fb14a5f32843e2c213ba6ebb31674ea2522f10c05639` |
| Harness SHA-256 | `3409f1b2f1f1bd8c689eccafa1d5f27de009b0a6e0dc74c4086aa0fe28c2e2fb` |

`EXECUTED_PASS`: clean `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` (source35/native0;
includes full namespace10/signer14+18/deferrednone), canonical unprivileged six-package build and
separate fresh container verification, and these five actual release-host commands in a disposable
installed real-root VM, each native0 with its mandatory marker:

```bash
bash tests/repository-checks.sh
bash tests/repository-checks.sh --require-full-namespace
/usr/bin/env -i HOME=/root LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
  /usr/bin/bash --noprofile --norc tests/publication-root-check.sh </dev/null
bash tests/keyring-rotation-checks.sh
env ARCH_LINUX_PRIVILEGED_ACCEPTANCE=true bash tests/keyring-rotation-checks.sh
```

Source35 log SHA-256 `051ee2f2183995c1f493e2e9e70fc40ade36b01d0a7aae9ea36df9ef7fa531cd`;
actual root gate log SHA-256 `f7ae55b1d7f844793827efd03be39c024dfa178df892081e06550f60a85d9456`.
Before/after source identities match; real UID map, quiescent captured PIDs and healthy images
were independently checked before exact-owned cleanup. These fixtures prove pre-merge boundaries,
not production signing. The later configured child build/readback/signing is a separate successful
execution, with actual bundle graph checked in memory without a development checkout or Git import.

| Actual new-child staged scenario | Status | Assertions |
| --- | --- | --- |
| `marble-gnome-btrfs-luks2-plymouth-systemdboot` | EXECUTED_PASS | 26 |
| `marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm` | EXECUTED_PASS | 17 |
| `minimal-dualboot-ext4-systemdboot` | EXECUTED_PASS | 17 |
| `minimal-ext4-systemdboot` | EXECUTED_PASS | 14 |
| `stock-gnome-btrfs-grub` | EXECUTED_PASS | 23 |
| `stock-gnome-btrfs-luks2-plymouth-grub` | EXECUTED_PASS | 22 |
| `stock-gnome-btrfs-luks2-plymouth-systemdboot` | EXECUTED_PASS | 21 |
| `stock-gnome-btrfs-systemdboot` | EXECUTED_PASS | 21 |
| `stock-gnome-ext4-systemdboot` | EXECUTED_PASS | 21 |

All nine results bind the same exact child, ISO, harness, signed snapshot and build/unsigned inputs.
Real password login, Wayland, lock/unlock, update/reboot, integrity, no failed units, clean poweroff
and image health passed where required.
Live installer cancellation, busy-resource cleanup and crash-path VM injection remain NOT_TESTED.
RECOVERY-01 accepts the specified source actual-handler failure/cancellation and concurrent
retention regressions; the nine successful scenarios do not establish those additional live paths. Plain Stock Btrfs/GRUB's23 assertions include real
read-only filesystem snapshot boot and normal-root return/owned cleanup; encrypted GRUB22 is
normal encrypted installation coverage. Marble26 additionally covers honest helper failure and
explicit GDM deactivation. Native result bytes and process chronology were independently checked.

`EXECUTED_PASS`: exact14 Phase-A, original14 byte-identical in finalized18, new acceptance/evidence
signatures, full production evidence validation, native core result hashes and `deferred=[]`.
The signed [acceptance JSON](https://github.com/snaplyze/arch-linux/releases/download/1.0.6/arch-linux-acceptance-1.0.6.json)
binds the full Phase-A map; evidence is1,948,353 bytes, below500MiB. Exact published asset map:

| Asset | Bytes | SHA-256 |
| --- | --- | --- |
| `BUILD-METADATA.json` | 737 | `b8cbf4689bac5ad75403a5fc2a1f17e8415a706b5c076d84bb2511e0dfecefec` |
| `RELEASE-SHA256SUMS` | 1107 | `d0c99ad072dc00ad61a639868e555fe2922671c32d0d8a049153e8d5146fc1cc` |
| `RELEASE-SHA256SUMS.sig` | 118 | `dc40d8940a3708339c2f018faa784e43dbf2054f6f0216acb36de77e6f14e42b` |
| `UNSIGNED-SHA256SUMS` | 1326 | `b5115ae0838e9c5f01a7fb14a5f32843e2c213ba6ebb31674ea2522f10c05639` |
| `arch-linux-acceptance-1.0.6.json` | 5283 | `13e6d8fa2139664fb7bab45042da0b156961f748e96fd656fc9d3c5bb5b23228` |
| `arch-linux-acceptance-1.0.6.json.sig` | 119 | `b159941b5d3b945c2799a2dec4efb304ab4704461526b84272a00b4bc0f10a1b` |
| `arch-linux-acceptance-evidence-1.0.6.tar.zst` | 1948353 | `c1d2a282d13d78eb95eff0ebe77544ee232b4214f6f81cd32fe1a20969db47a1` |
| `arch-linux-acceptance-evidence-1.0.6.tar.zst.sig` | 119 | `3b03534ec13401ab21c398c36488b6646c3b54b5ece42760e7227cae25e31780` |
| `arch-linux-installer.sh` | 402255 | `ebb90209b6d407f8bb54091ef4112267852269bf5744af9c54df8a8308dff55a` |
| `arch-linux-installer.sh.sha256` | 90 | `a3ef1368b540a44b802fc041c128c201a91815d647550841d96a0eea534ac776` |
| `arch-linux-installer.sh.sig` | 119 | `f98ad9d66e69ddaf36d57e0a3eb519bb16507c6079cfe92fd41adc7a622b0d0c` |
| `arch-linux-repository-1.0.6.tar.zst` | 5732653 | `25a129f7fa0f91d9ec85d0418ba938dd62e7fea0052838f76b89b3292a795496` |
| `arch-linux-repository-1.0.6.tar.zst.sha256` | 102 | `b357b8e150c74db7872d12309562ea2986686b0780545b444bf668c7f5361f8f` |
| `arch-linux-repository-1.0.6.tar.zst.sig` | 119 | `bd8b72494b61ba462a37de3af0e24d71c956f99335660b3226c0b9338643caa8` |
| `arch-linux.gpg` | 568 | `8959dfd96fd94349d505f18a6d3ef0a3bfcd9fad53291343388f787f9dbb9c6f` |
| `install.sh` | 28213 | `ee9f9c085acf6c8d2519fb8d76003da101740052afe5bf2a16bbc8957506f663` |
| `primary-fingerprint` | 41 | `7e12b5e2a2ce9ed2881e06d80054a969465eea72f917282f25f27ae02cf66824` |
| `signing-subkey-fingerprint` | 41 | `471e476b51923eb1afe73609a7ef4aef3fbc1e1c2b09ba3f77e9f1f349643b69` |

`EXECUTED_PASS`: unauthenticated HTTPS Release18 byte equality to accepted finalized18 and
annotated tag→child/run binding; all25 Pages files (23 named objects plus manifest/signature)
match the independently safe-extracted signed snapshot. Public API requires immutable=true and
exact canonical asset sizes/digests; downloads require exact size, EOF and SHA-256 under a30m
outer process deadline. Root and independent read-only checks accepted actual bytes.

Proof receipts: source graph `f719cf2597cb02edd34b7dbe560cb06891896dc5b89d0cd56ac29a702a8e2579`,
Phase-A `7838f402db5be938d7649f40abb733df73bb560fbebf0a43bb3a8e51b66ec16a`,
final18 `b69d534ce6755cf9af235edb804d3e05bb05a9660b1b1570f3e95721f02227c5`,
public bytes `957a3c88f0e95d5405f6fa8bb048d195684848939c9d174e9d0c49ad3311bb67`.
They are retained with compact native evidence in the existing external evidence register;
no signing secrets, VM disks or generated package outputs enter source.

`EXECUTED_PASS`: fresh public-only Marble/GDM VM, native0 with19 assertions. The configured
workflow completed SUCCESS. Public run `marble-20261004T162511Z-cc51576a` consumes only
immutable tagged bootstrap/verified Release installer and signed public Pages. It passed actual
HMP password login and Wayland, lock/unlock, full update, reboot/second login, package integrity,
zero failed units, clean poweroff, no matching QEMU process and healthy image. The compact
public artifact11308433140 binds the same accepted child/source/ISO/harness/snapshot/build inputs;
its manifest/signature and23 repository objects match the signed archive and public byte proof.
Native result SHA-256 `13de92af4ecc355529ae734674a7966529c62209adbb7d0d066ebf523b0d25e8`;
public archive SHA-256 `a227c1c3078672beea8c66163e2add16815ce2f43253963c7d6502d437fb1f4f`.
Public19 and staged26 remain distinct: staged-only legacy/helper-failure/removal checks are
not relabeled as public execution. Optional screenshots are retained as diagnostic evidence.

Local final-document verification uses `python3 tests/docs-checks.py`, `git diff --check` and
`PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`. Working-doc source36 passed native0;
the clean document-commit command/tree/receipt is bound in the existing register.
It does not replace or relabel the release-child VM/source identities above.

Clean local documentation commit `30d4a162ed99141c4ccd2b43273a90f1fda0b756` (tree `895fb77ea77e2f66ef5bf8cbb49ba6f21572004b`, canonical SHA-256 `368587520f60e525c9ede887e08b139e77aa42597dbbfc6da2705422339c04d6`) passed `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`, source37/native0/session71065; log SHA-256 `ad9f3e402e3bcfaf772d44c3b88ec422e4eba3df6a948b91d7dcd8610ece3ccd`. This result belongs to that exact documentation tree. Later documentation edits require fresh applicable checks; the evidence register preserves each exact tree/result.
Historical predecessor failures, 1.0.5 media qualification and older release results retain their
original identities. Final documentation was initially retained in localmain commits. A subsequent
explicit owner request authorizes checked PR/main publication of these documents. Record its exact
outcome in the same evidence register after publication. This publication requires no new installer release.

## Historical audit record

The [single registry](PLAN.md#review-findings) records the October 2 review and October 3
documentary follow-up, coverage, open findings and exact check outcomes. Documentary corrections
do not fix product defects. Fresh builds, production signing, crash/race acceptance, real account
creation and real VM installation were not executed by this follow-up; they remain NOT_TESTED
(`NOT_RUN_ENVIRONMENT` in the check-status vocabulary below).

## Public readback of release 1.0.5

October 3 execution independently downloaded all 18 immutable [1.0.5 Release assets](https://github.com/snaplyze/arch-linux/releases/tag/1.0.5),
checked their API size/SHA-256 map, exact-12 `RELEASE-SHA256SUMS` coverage and all five
release detached signatures against the committed public certificate and exact signing subkey.
Public trust files match the committed bytes. The Pages manifest and signature match the signed
repository archive bytes; all 23 named repository objects match size/hash, and the manifest,
two databases and six packages pass detached signature verification. The semantic database
checker additionally accepted the real published database/package pair.

| Binding | Value |
| --- | --- |
| Release commit | `61add3e0b2c20adbbdd425494eae02ddec0a3bac` |
| Release tree | `b5ca51e80277d93541d00a305490ac818d629a33` |
| Canonical source SHA-256 in signed acceptance | `02816596c2e2e72cddb31b357723660685e4c77fce929c76b04f5e21dee18d37` |
| Repository archive SHA-256 | `79413af54fca28fc1afef9fbfe6dea24875470d1a3cd65a6c459eb85bde26474` |
| Build metadata SHA-256 | `c6d7a812737b41e52e8ea3cb59613ac2ceb0e4a0e601d44f6de99820661972da` |
| Unsigned manifest SHA-256 | `97a821f50df2ab7a523107e0b9f7f956fcce6cc02189437d758c4c429bc6deae` |

Historical status: `EXECUTED_PASS` for public byte/signature readback. At that readback README commands pinned 1.0.5.
Its signed acceptance still describes the three historical September ISO runs; it is not an
October installation or corrected-candidate PASS. Subsequent corrected-release execution is recorded above and in [the registry](PLAN.md#registry). The verified 1.0.4 evidence below
keeps its original identity and outcomes.

## Verified release 1.0.4

[Release 1.0.4](https://github.com/snaplyze/arch-linux/releases/tag/1.0.4) was published on
2026-09-17 with `immutable: true` and exactly 18 assets. Its annotated tag resolves to commit
`c4c46588b8eab987c3c29e6548b81bd2f6b4217f`, tree
`b973c979e781e06af30fb18f0855b9724c941e0c`. The reviewed origin main commit is
`e4e68bb58ef3a61c2de9938223a4fd214d2f6e76`. These identities describe that release, not later
changes to `main`.

The [Release workflow](https://github.com/snaplyze/arch-linux/actions/runs/35164378553)
completed successfully. Its build, independent artifact readback, signing-boundary checks, staged
VM matrix, finalization, annotated tag, Pages deployment and immutable publication passed.

| Executed scenario | Result | Functional assertions |
| --- | --- | --- |
| Minimal TTY / ext4 / systemd-boot | EXECUTED_PASS | 14 |
| Stock GNOME / Btrfs / LUKS2 / GRUB | EXECUTED_PASS | 22 |
| Marble / Btrfs / LUKS2 / systemd-boot / Marble GDM | EXECUTED_PASS | 24 |
| Public-only Marble installation from Release and Pages | EXECUTED_PASS | 19 |

The signed [acceptance JSON](https://github.com/snaplyze/arch-linux/releases/download/1.0.4/arch-linux-acceptance-1.0.4.json)
and [evidence archive](https://github.com/snaplyze/arch-linux/releases/download/1.0.4/arch-linux-acceptance-evidence-1.0.4.tar.zst)
contain the three staged results and their exact input bindings. Both have detached signatures in
the Release. The final public VM result is a separate workflow artifact; it does not modify the
already published acceptance JSON. Public attempt 3 passed; the earlier HTTP download failure and
connection reset remain failed attempts, not relabelled successes.

The staged Marble run includes legacy GTK3-package replacement, fresh-user activation and startup
of Nautilus, Ptyxis, Settings and Boxes in both color-scheme states. Startup checks and diagnostic
captures do not establish exhaustive visual compatibility. No new claim about every storage,
bootloader, dual-boot or physical-hardware combination follows from this three-scenario release.

## Source evidence

Contains exact source identity and the commands/statuses for syntax, version, bootstrap, static,
function, Marble, package metadata, documentation, portability, secret, agent, maintenance,
repository fixture and ShellCheck tests. It must not include generated package or VM outputs.

## Build evidence

Contains the clean Arch environment identity, canonical unsigned package closure,
`UNSIGNED-SHA256SUMS`, package metadata and verifier result. Monthly A+B comparison is advisory and
is recorded separately from the required canonical release build.

## QEMU evidence

Contains the accepted ISO identity, QEMU/OVMF versions, new qcow2 and independent VARS identities,
scenario configuration, installer/repository identities and a structured result. The exact release
matrix is Minimal TTY/ext4/systemd-boot, Stock GNOME/Btrfs/LUKS2/GRUB and
Marble/Btrfs/LUKS2/systemd-boot with the separate experimental Marble GDM opt-in. All three staged
runs bind the same independently verified production-signed repository archive, source commit/tree,
build-metadata hash, unsigned-manifest hash and frozen Arch ISO hash.
The staged inputs are the exact 14 Phase-A assets, whose signed checksum manifest covers exactly 12
non-self files. Finalization is allowed only after all three functional PASS results and preserves all
14 bytes while adding signed acceptance JSON and evidence archive for exact 18.

Each scenario retains a short compressed installer log, input and tool hashes, the signed repository
manifest/signature and package/database hashes, functional assertions and a structured PASS or FAIL.
A FAIL includes the failed phase and non-zero exit status. Check actual GDM password login and the
resulting Wayland session, lock/unlock, update and repeated login. Screenshots help diagnose the
result but are optional; no sampling interval or human receipt is required.

After each scenario remove its qcow2, OVMF VARS, payload, extracted repository and TLS runtime,
check that its QEMU/server processes exited, and retain `qemu-img check`. Never retain passwords,
private keys, passphrases or recovery material. Keep reports compact and separate from source;
the release evidence archive has a 500 MiB storage cap, not a frame timing or visual certification
requirement. Do not scan VM disks as if they were text logs.

## Release evidence

Contains signed repository/release-asset verification, immutable release asset identities, Pages
readback and the final public VM result. It is created only after the corresponding operations and
cannot retroactively change source/build/QEMU results. For the generated release child, provenance
also binds the exact successful origin main commit/tree and the deterministic transform record.
The acceptance JSON binds the commit/tree/canonical source SHA-256, build/unsigned/snapshot hashes,
the exact Phase-A name/hash/size map and aggregate, its manifest hash, three PASS verdicts,
evidence no larger than 500 MiB and `deferred=[]`.

The final public Marble/GDM VM carries no local product bytes: it downloads the immutable tagged bootstrap, verifies the Release installer and
public key, executes only that verified installer, and obtains project packages and databases from
the exact public Pages URL under `PackageRequired DatabaseRequired TrustedOnly`. Public readback
verifies signed `RELEASE-SHA256SUMS`, the exact archive digest and signature, byte equality between
the archive and Pages manifests/signatures, schema-2 source/build identity, all 23 Pages object
hashes/sizes, and all package/canonical-database signatures. Merely echoing an expected archive hash
or validating an unbound Pages manifest is not public readback evidence.

## Status discipline

Use exactly one status per check: `EXECUTED_PASS`, `EXECUTED_FAIL`, `REVIEWED_ONLY`,
`NOT_RUN_ENVIRONMENT` or `NOT_APPLICABLE`. Record exact commands for executed tests. Absence of a
required environment is not a PASS.
