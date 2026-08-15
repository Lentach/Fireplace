# 2026-08-15 — Workstation NIC outage: IOMMU DMA fault fixed; DNS flakiness is separate and OLDER

**NO REPO CODE CHANGED. NO DEPLOY. Fireplace product untouched.** This session is **workstation
infrastructure**, not product work — filed here because `AGENTS.md` §1 mandates a summary at task end.
For Fireplace state read the other 08-15 file, `2026-08-15-session-decryption-failed-root-cause.md`;
nothing here touches backend, frontend, or prod.

Machine: `DESKTOP-6MCRU9B`, MSI **B150M PRO-VDH (MS-7982)**, Win11 26100.
NIC: **Realtek RTL8168H**, `PCI\VEN_10EC&DEV_8168&SUBSYS_79821462&REV_15`, at **PCI bus 2, device 0,
function 0** — the only device on bus 2. The whole diagnosis turns on that address.

---

## 1. Verdict

Two faults, **not** a common cause. The owner challenged this ("years of nothing, then two at once —
doubt it's unrelated to the new driver"); it was tested rather than asserted. See §4.

| | Fault A | Fault B |
|---|---|---|
| Symptom | net dies mid-game, only a cable replug fixes it | "Internet access" shown, nothing resolves |
| First seen | 08-11 (≥5 occurrences **before** any driver change) | ≥ 07-18, recurring every few days |
| Mechanism | IOMMU blocks the NIC's DMA → miniport wedges, PHY link stays up | public resolvers stop answering :53 for ~20 min |
| Fix | Realtek driver `1.0.0.14` (2017) → `10.79.50.1003` (2025) | reverted Ethernet to DHCP DNS (`192.168.1.1`) |
| Status | **fixed**, survived a full clean gaming session | **transient, self-resolved**; cause upstream, not local |

---

## 2. Fault A — IOMMU DMA fault against the NIC

Net died **only** while playing *Heroes of Might & Magic: Olden Era*; the PS5 kept streaming Twitch. The
PS5 is on **Wi-Fi** and never touches this NIC, so it was never evidence about the wired path.
Reinstalling the game changed nothing: the game is the **trigger**, not the fault. Its match traffic
(bursts of small UDP + scatter-gather TX) is the only workload on the box that walks the bad path — which
is why a machine that was fine for years broke the week this game arrived.

`Device: 0x200` decodes to **bus 0x02, dev 0x00, fn 0x0** = uniquely the Realtek NIC.
Full fault: `FaultInformation: 0xFEF04000  FaultReason: 0x6  ExtendedData: 0x0`.

| | IOMMU fault (`HAL` id 15) | link dead (`NCSI SuspectArpProbeFailed`) | NDIS notices (`WerKernel` 1001) |
|---|---|---|---|
| 08-11 | (throttled) | 03:32:59 | 03:33:20 |
| 08-12 | 03:11:34 | 03:12:16 | 03:13:13 |
| 08-13 | 01:57:03 | 02:01:17 | — |
| 08-14 | 19:08:58 | 19:09:51 | 19:10:35 |
| 08-15 | (throttled) | 00:26:40 | — |

`VBS status: 2` + `HypervisorEnforcedCodeIntegrity Enabled=1` ⇒ Memory Integrity on ⇒ VT-d DMA remapping
actively polices device DMA. The 2017 inbox driver DMAs outside its mapped buffers; the IOMMU blocks it;
the DMA engine stalls. **The PHY link stays up at 1 Gbps**, so Windows never re-initialises the device and
reports "connected" throughout. A cable replug forces a PHY reset → rings and DMA mappings rebuilt →
traffic resumes. That is exactly why *only* replugging worked.

### The fix
- Windows Update had **no** Realtek NIC driver (8 Intel chipset entries only) — it would never self-heal.
- MSI OEM package `https://download.msi.com/dvr_exe/mb/realtek_pcielan_w10.zip`, 11,234,640 bytes,
  sha256 `3ed915d072dfca587facdda8645950804d3d7a6194ca9c95c58b84eed3e5d687` (`_w10`/`_w11` identical).
- **Verified before installing:** `rt640x64.inf` line **9484** declares this exact device,
  `…SUBSYS_79821462&REV_15`, tagged `;MSI`, bound to `RTL8168H.ndi`; `DriverVer = 10/03/2025,
  10.079.50.1003`. `rt640x64.cat` Authenticode **Valid**, WHQL-signed by *Microsoft Windows Hardware
  Compatibility Publisher*; `rt640x64.sys` **Valid**, *Realtek Semiconductor Corp.* via DigiCert.
- `pnputil /add-driver … /install` → exit 0, published `oem35.inf`, bound live. **No reboot, link never
  dropped.** `Microsoft 1.0.0.14 / 2017-08-10` → **`Realtek 10.79.50.1003 / 2025-10-03`**.

**Result:** a full gaming session with zero recurrence; `IOMMU 0 · ARP-probe 0 · NDIS dumps 0` since 00:50.

---

## 3. Fault B — DNS, and the correction

Ethernet carried a **hardcoded** `NameServer = '8.8.8.8,1.1.1.1'`
(`HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{cda26cf3-…}`), overriding
`DhcpNameServer = 192.168.1.1`. At ~05:41–05:55 both public resolvers **pinged fine but timed out on
every DNS query (~11.2 s)** while the router answered in 82 ms. NCSI logged `SuspectDnsProbeFailed` ×3.

Reverted to DHCP DNS; verified Wi-Fi-disabled: DNS 3–55 ms, Steam API `HTTP 200`, Google `204`,
Cloudflare `200`, 300 gateway pings / 0 lost.

### ⛔ CORRECTION — I first called this "the ISP blocks port 53". That is WRONG. Do not repeat it.
Re-tested ~25 min later, 40 samples per resolver, cache-defeating unique names:

```
resolver       answered timeout  avg ms   worst ms
8.8.8.8        40       0        31       290
1.1.1.1        40       0        28       41
192.168.1.1    40       0        27       52
```

`8.8.8.8` and `1.1.1.1` are **not blocked**. It was a **~20-minute transient**, and the permanent-block
claim was over-extrapolated from one failed sample. Reverting to the router's resolver is still the right
default (it is what DHCP hands out, and it kept answering through the blip) — but not for the reason
originally given.

---

## 4. "Are the two really unrelated?" — the challenge, and the tests that settle it

The owner's objection was reasonable: two failures inside 12 h after years of quiet smells like one cause,
namely the new driver. Both halves were tested.

**Test 1 — could the new driver break DNS?** The only plausible driver mechanism is a broken **UDP TX
checksum offload**: UDP would leave with bad checksums and be dropped upstream while ICMP ping still
worked, which reproduces "ping fine, DNS times out" exactly. Result, with offload **still enabled**:

- UDP/123 NTP → `216.239.35.0` **OK 26 ms**, `162.159.200.1` **OK 13 ms**, `129.6.15.28` **OK 103 ms**
- raw UDP/53 socket → `8.8.8.8` **OK, 124 bytes, 28 ms**
- TCP/53 and UDP/53 to all four resolvers **OK**

A checksum-offload defect breaks *all* outbound UDP, not port 53 selectively. **Mechanism excluded.**

**Test 2 — did DNS trouble predate the driver?** `Microsoft-Windows-DNS-Client` id **1014**, *"none of
the configured DNS servers responded"*, last 30 days:

`07-18 20:35` (**`p2p-sto2.discovery.steamserver.net`** — a real Steam lookup, not just wpad),
`07-18 23:29`, `08-01`, `08-04`, `08-05`, `08-06`, `08-10`, `08-11`, `08-13`, `08-14`, then `08-15 05:49`.

Plus `NCSI SuspectDnsProbeFailed` on **07-27** and **08-13**. **Ten-plus occurrences over a month, every
one on the old 2017 driver.** The symptom is chronic and long predates the change; it went unnoticed
because it mostly struck invisible `wpad` lookups and short windows.

**And Fault A cannot be driver-caused either:** it fired **five times before** the driver was installed
at 00:50 (08-11, 08-12, 08-13, 08-14, 08-15 00:26). A driver installed at 00:50 cannot cause failures
dated 08-11.

**Conclusion:** unrelated — now demonstrated, not asserted. "Years of nothing" is explained by *Olden Era*
being a new workload, not by anything changed this week.

---

## 5. Wi-Fi dongle — device node removed, `ConfigFlags` reset

TP-Link Wireless MU-MIMO USB Adapter, `USB\VID_2357&PID_0138\123456`, service `RtlWlanu`.

`Disable-NetAdapter -Name 'Wi-Fi'` was used during the Ethernet-only proof. The owner then **physically
unplugged** the dongle, making it a phantom (`Present: False`, `Problem: CM_PROB_PHANTOM`), so
`Enable-NetAdapter` was impossible — no adapter to enable.

**The disable had persisted as `ConfigFlags = 0x00000001` (`CONFIGFLAG_DISABLED`) on the phantom node** —
left alone the dongle would return **disabled** on replug and look like dead hardware. Cleared, elevated:

1. `Enable-PnpDevice` → failed, `Generic failure` (expected on a not-present device)
2. `Set-ItemProperty … ConfigFlags = 0` → **succeeded**
3. `pnputil /remove-device 'USB\VID_2357&PID_0138\123456'` → **"Device removed successfully"**, exit 0

Verified after: `Enum` key **gone**, no lingering TP-Link records, driver package **`oem25.inf`**
(`netrtwlanu.inf`, Realtek `1030.52.1216.2025`) **still in the store** ⇒ re-enumerates clean and
**enabled**, auto-installing on replug. No user action required.

⚠️ `.rewifi.ps1` printed **"NOT CLEARED"** — that verdict is **wrong**, a bug in my own verification line
(`Show-Flags` emitted output *and* returned ⇒ `Object[]` ⇒ `-band` threw `op_BitwiseAnd`). Both real
operations had already succeeded; an independent re-check confirmed. Trust the re-check.

---

## 6. Killed hypotheses — do not resurrect

- **Modem / router / ISP (for Fault A).** PS5 streaming proved only that the WAN was up; it is on Wi-Fi
  and shares nothing with this NIC but the router.
- **Corrupt game install.** Uninstall/reinstall changed nothing.
- **Ephemeral port exhaustion.** Real `Tcpip` 4231/4266 warnings exist (08-04, 08-05, 08-10 ×2, 08-13),
  and a link reset *would* free the pool — but **none occurred after the 08-13 16:16 boot**, so they
  cannot explain 08-14/08-15. Excluded on timing.
- **"The 03:55→04:15 Ethernet disconnect was a link flap."** It was **sleep** — `Kernel-Power id=42,
  Sleep Reason: System Idle` 03:55:13, resumed 04:15. No media events in 6 h.
- **"ISP permanently blocks port 53."** Mine, and wrong — see §3.
- **"New driver's UDP checksum offload broke DNS."** Tested and excluded — see §4.
- **Green Ethernet / EEE / Gigabit Lite / Power Saving Mode** are still **Enabled** (vendor defaults) and
  there have been **no link flaps**. Left alone deliberately so as not to confound verification. They are
  the *next* lever only if the link starts actually dropping — a different symptom from the silent freeze.

## 7. Signal-reading notes

- **`NCSI CapabilityReset` is benign** — fires on every sleep/resume and boot; ~100 of them, meaningless.
  **`SuspectArpProbeFailed` is the real hang signal.** Never count the former.
- `Microsoft-Windows-NDIS/Operational` is **disabled** here (`RecordCount` empty). Use
  `Microsoft-Windows-WerKernel/Operational` id 1001 with `Component NDIS`.
- NDIS's requested live dumps were **never written** (`ThrottleCheckResult 0x21`,
  `STATUS_ALLOTED_SPACE_EXCEEDED`); `C:\Windows\LiveKernelReports` is empty. **The event is the evidence.**
- **HAL throttles repeated identical IOMMU faults** — a missing `HAL` id 15 next to an outage does not
  clear the IOMMU. 08-11 and 08-15 00:26 both lack one.
- **One failed DNS sample is not a blocked port.** Sample tens of times with unique names before
  concluding anything about a resolver (§3 is the cautionary tale).

## 8. Tooling traps

- The harness `bash` tool **expands `$_`, `$e`, `$p` before PowerShell sees them**, mangling inline
  `powershell -Command "…"` into syntax errors (`.netdiag7.ps1.DeviceClass`, `if () {`). Write every
  non-trivial PowerShell to a `.ps1` and run `-ExecutionPolicy Bypass -File`.
- `Get-WinEvent` across *all* logs for a 20-minute window took **300 s and timed out** once. Scope to
  specific `LogName`s, write to a file, filter the file with the `grep` tool — not `Where-Object`.
- Elevation works via `Start-Process … -Verb RunAs -Wait` with the script writing a transcript to a known
  path; the parent shell cannot see the elevated child's stdout.

## 9. Artifacts left on disk (outside the repo)

- `C:\Users\Lentach\Desktop\reset-nic.ps1` — self-elevating `Restart-NetAdapter` + gateway/internet probe;
  the software equivalent of replugging the cable if the NIC ever wedges again.
- `C:\Users\Lentach\Desktop\realtek-lan\` — driver zip plus `install.log`, `dnsfix.log`, `ethtest.log`,
  `wifi-reenable.log`. Safe to delete; the driver lives in the system store.

All temporary diagnostic scripts written into the repo tree were removed; `git status` shows only the
owner's own pre-existing `.cursor/session-summaries/` changes.

## 10. Open / watch

- **Fault A recurrence:**
  `Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-HAL';Id=15}` —
  nothing after **2026-08-14 19:08:58** means it is still dead.
- **Fault B is unexplained, only characterised.** The ~20-min transient's cause (upstream ISP blip vs
  router hiccup) was not identified; it self-resolved. If it returns, capture whether the router resolver
  also fails — that is the discriminator between local and upstream.
- **Do not re-add static `8.8.8.8/1.1.1.1` here.** Not because they are blocked (they aren't) but because
  the DHCP resolver stayed up through the blip and something may re-write static entries (VPN /
  "optimizer" tool). If off-ISP DNS is genuinely wanted, use DNS-over-HTTPS.
- `OutboundPacketErrors: 15` on Ethernet is **static** — unchanged across 340 pings, so boot-time link
  negotiation noise. Worth a glance only if it starts climbing.
