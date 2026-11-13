# Compliance matrix (Super Flow, Store edition)

| Guideline / rule | Status | How |
|---|---|---|
| 2.4.5(i) App Sandbox | done | `SuperFlow-AppStore.entitlements`; build check |
| 2.4.5(i) minimal entitlements, no temporary exceptions | done | entitlements.md |
| 2.4.5(iv) no feature-adding downloads; reviewable | done | data-only, pinned hashes; review-notes.md explains the Download button |
| 2.4.5(v) no self-update | done | UpdateKit compiled out; build fails if the GitHub releases URL is present |
| 2.4.5 / 4.x Accessibility for non-accessibility purpose | **review risk** | ⌘V posting kept (needs Accessibility); copy-only mode ("Paste automatically" off) ships as fallback. Owner decision |
| 2.5.1 public APIs only | done | Core Audio process taps, EventKit, CGEventTap (listen-only), CGEventPost — all public |
| 2.5.2 no downloaded code | done | weights only |
| 2.5.14 recording consent + indicator | done (UI exists) | meeting prompt asks; Flow Bar shows listening/recording; OS indicators |
| 4.2.3 disclose size before download | done | consent card with total size; autoDownload off by default |
| 5.1.1 privacy / purpose strings | done | Info.plist strings; NSAppleEventsUsageDescription removed in Store |
| 5.1.2 data use | done | nothing collected; App Privacy = Data Not Collected |
| Quarantine xattrs stripped | done | `xattr -cr` before signing in build-app.sh |
| Universal binary | ready | `UNIVERSAL=1 ./scripts/package-appstore.sh` |
| Signing / provisioning / upload | **blocked: credentials** | package-appstore.sh fails loudly without identities |
| GPL | none | dependency audit |
| Export compliance | owner to confirm | OS HTTPS + hashing only |
