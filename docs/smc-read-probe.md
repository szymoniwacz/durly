# Read-only Intel SMC probe — issue #6

Scope: manual diagnostic reads of BCLM and BFCL on MacBookPro11,5 / Intel / Monterey 12.7.6 only. No SMC write selector, no arbitrary keys, no elevated privileges, no polling, no changes to PowerControl capability. A read is not evidence that a write is safe.

## ABI and provenance

The private AppleSMC IOKit interface is researched against [SMCKit embedded in bclm v0.1.0](https://github.com/zackelia/bclm/blob/v0.1.0/Sources/bclm/SMC.swift), not a supported public Apple API. Durly uses an explicit zero-initialized 80-byte Intel little-endian frame rather than relying on Swift struct padding. Key at offset 0, size at 28, type at 32, controller result at 40, operation at 42, payload at 48. External method 2; internal operations 9 (metadata) and 5 (read) only. Metadata must be size 1 and type ui8 (trailing space). Exact 80-byte responses required. Kernel return and controller result checked separately. The status field has no verified success semantics; no assumption about echoed key or populated metadata in the data reply. Raw bytes 0–255 are diagnostic evidence, not validated charge percentages or safe baseline values.

Each explicit probe opens one connection, independently reports both keys, closes it, and releases the service. No automatic retries or polling. The UI executes the probe off the main queue, labels results as last manual read, and never uses them to authorize control. The private driver call has no proven bounded timeout; a stalled call may leave the probe button disabled until app restart. A failure to close is reported, not hidden. No dependency on bclm/AlDente at runtime.

## Local acceptance (pending)

1. Build and run using existing CLT scripts. Confirm no compiler errors and portable tests pass.
2. Open the popover and enable Show diagnostics. Click Read SMC charge keys. Record exact result for each key (including errors). No sudo, no writes.
3. Confirm the app stays read-only and ordinary battery telemetry remains available. Repeat the read once to check connection lifecycle. An external controller may change the values between reads; do not infer ownership.
4. If metadata differs, record the error; do not relax the decoder or enable writes without evidence. BFCL may be missing. The original BFCL baseline from issue #3 is unknown and cannot be reconstructed from this probe.

Native ABI compatibility and hardware observations are not established by portable unit tests. Production write gates in [feasibility report](intel-charge-control-feasibility.md) remain unchanged.

## Upstream notices

Protocol facts referenced from the above source; retained notices for SMCKit and bclm.

```text
The MIT License

Copyright (C) 2014-2017  beltex <https://beltex.github.io>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

```text
MIT License

Copyright (c) 2020 Zack Elia

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
