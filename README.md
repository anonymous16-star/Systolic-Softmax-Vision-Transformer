# BoostViT + LOGOS Accelerator (Xilinx ZCU104, XCZU7EV)

Reimplementation of the BoostViT Booth-serial skipping accelerator with the
**LOGOS fully-integer log-domain softmax engine**, targeting the
**Xilinx Zynq UltraScale+ XCZU7EV (ZCU104)** at the full paper datapath.
INT8, target 300–500 MHz (the LOGOS paper reports a 3.038 ns softmax-engine
critical path, i.e. ~328 MHz; see §8).

Paper reference (LOGOS, "This Work" row of its Table II):
**207.3 kLUT, 0 DSP, 58 BRAM, 852.1 GOPs** on ZCU104.
BoostViT [1] reference row (same table): 211.6 kLUT, 198 DSP, 539.5 BRAM, 853.3 GOPs on ZCU102.

This deliverable closes the gap from the v1 89.5 kLUT baseline toward
paper parity by adding the 5 missing Fig. 6 blocks, routing DRAM-side
DMA, and fixing three blocks that Vivado DCE'd in v1.

> **Part/board note.** The part string `XCZU7EV-FFVC1156-2-E` is the **ZCU104**
> device (the ZCU102 uses the XCZU9EG). Earlier revisions of this README said
> "ZCU102 (XCZU7EV)", which mixed the two. The LOGOS paper's FPGA results are
> also on ZCU104, so this README now uses ZCU104 throughout.

---

## 0. Relationship to the LOGOS paper

LOGOS is the softmax / normalization engine. BoostViT-style Booth-serial
skipping is the underlying compute substrate (the paper treats it as given).

Paper Fig. 1 block → RTL mapping:

| Paper block | RTL module(s) |
|---|---|
| Controller (outer + inner loop FSM) | `boostvit_controller.sv`, `outer_loop_ctrl.sv` |
| BSPE systolic array (16×16 Booth-serial PEs, K-stationary) | `BSPE.sv`, `systolic16.v`, `systolic_16x16_softmax.sv` |
| SM unit (exp / log, softmax + LayerNorm) | `exp_cal.sv`, `logcalc_v2.sv`, `softmax_from_exp_16.sv`, `softmax_16.sv`, `sm_unit.sv`, `layer_norm_16.sv`, `ln_array_16x16.sv` |
| Linear projection unit (Q/K/V + MLP) | `linear_proj.sv` |
| Accumulator (wide output bank) | `wide_accum_bank.sv` |
| AXI burst DMA interface / DRAM | `axi_burst_if.sv` |
| Output buffer (DP RAM) | `ram_dp.sv` |
| Head concat unit | `head_concat_unit.sv` |

### 0.1 LOGOS algorithm summary (from the paper)

1. **Max subtraction:** 16-way comparator tree, `x' = x − x_max`, signed Q1.7, clipped to [−128, 0].
2. **Multiplier-free exp:** `x' = a·ln2 + r`; `1/ln2 ≈ 1 + 1/4 + 1/8 + 1/16 + 1/128 = 1.4453125`
   (shift-add); 8-segment piecewise mantissa with LUT `{128, 144, 164, 185, 210, 238, 250, 255}`
   (profiled on DeiT attention logits: mean error 0.31 → **0.186 ULP**) plus shift-add interpolation.
3. **Accumulation:** balanced 16-input adder tree, worst case 16 × 255 = 4080 → fits in **12 bits**.
4. **Multiplier-free log:** leading-one detect + 8-segment LUT + shift-add interpolation
   (`ln x = k·ln2 + ln m`, m ∈ [1,2)). A **widened** log unit handles the row sum `e_s`;
   a standard one handles individual `e_i`. Mean error **0.286 ULP**.
5. **Divider-free normalization:** `y_i = ln(e_i) − ln(e_s)`; one row-wise log shared by all
   elements ("single-log normalization"). Output is signed **Q3.5 log-softmax**.
6. **Multi-tile normalization:** partial sums merged in the log domain,
   `ln(S_a + S_b) = max(ln S_a, ln S_b) + ln(1 + e^(−|ln S_a − ln S_b|))`,
   with the correction term in a compact LUT.

### 0.2 Paper alignment status

| Item | Status |
|---|---|
| exp / log accuracy (0.186 / 0.286 ULP mean) | **Matches** (§7) |
| 12-bit exp-sum width (`smu_es_sum`) | **Matches** |
| Q1.7 exp input / Q3.5 log output | **Matches** |
| LN on a 16-token batch register | **Matches** (`ln_batch_reg`, §2.2) |
| Single wide log per row | **To verify** — confirm `logcalc_v2` / `sm_unit` use a widened unit for `e_s` |
| Exp LUT contents / 1/ln2 shift-add constant | **To verify** — diff `exp_cal.sv` against the §0.1 table (RTL is protected; check only) |
| Log-domain output consumed by the ·V stage | **Open** — the current testbench checks a linear-domain softmax summing to 128/128 (Q1.7); the paper feeds Q3.5 log-softmax onward. Confirm which form `attention_head` consumes. |
| **Multi-tile log-domain merge (correction LUT)** | **Gap — not implemented.** DeiT-Tiny rows (N = 196) span 13 tiles of 16; `sm_unit` needs a `max + LUT(1+e^−|Δ|)` merge stage and partial-sum storage per row. |
| Piecewise INT8 GELU, <3 % error on [−2, +2] | **To verify** — check `gelu_approx_16.sv` against this spec |
| Skip rate / BSPE | Unchanged (BoostViT substrate) |

---

## 1. File manifest (35 files + this README)

### 1.1 Core RTL (never modified — user-protected mandate)

- `BSPE.sv`            — Booth-Serial Skipping PE (paper Fig. 5).
- `Boothencoder.sv`    — 8-bit → four 3-bit Booth codes.
- `Boothmul.sv`        — 3-bit Booth partial-product multiplier.
- `Boothunit.sv`       — Pipelined Booth stage with skip short-circuit.
- `Fifo.sv`            — FWFT FIFO (depth-16, power-of-2 fix).
- `exp_cal.sv`         — LUT-based e^x, Q1.7, 0.186 ULP mean accuracy (LOGOS exp unit).
- `logcalc_v2.sv`      — LUT-based ln(x), Q3.5, 0.286 ULP mean accuracy (LOGOS log unit).
- `softmax_from_exp_16.sv` — Per-row softmax normalisation.
- `softmax_16.sv`      — 16-wide softmax wrapper.
- `layer_norm_16.sv`   — Single-token LN (16-dim).
- `systolic16.v`       — 16×16 BSPE raw systolic array.
- `systolic_16x16_softmax.sv` — Systolic + row-end expcalc (attention path).
- `linear_proj.sv`     — Linear projection (shared Q/K/V/WO/MLP).
- `attention_head.sv`  — One attention head (Q·K^T + softmax + ·V).

### 1.2 Phase-4 compute blocks (v1, reused)

- `gelu_approx_16.sv`  — 16-lane INT8 GELU approximation (combinational).
- `residual_add_16.sv` — 16-lane saturated INT8 adder (combinational).
- `ln_array_16x16.sv`  — **16 parallel LN instances** — now fully driven in v2.
- `ram_dp.sv`          — Dual-port BRAM-inferring RAM.
- `sm_unit.sv`         — Paper SM Unit (shared exp + accum + reciprocal/log) — now **observable**.

### 1.3 Phase-5 NEW modules (v2 additions for paper parity)

- `wide_accum_bank.sv`  (**+8-12 kLUT**) — 16× 24-bit accumulators with shift/saturate output. Emulates paper's wider partial-sum datapath.
- `axi_burst_if.sv`     (**+5-8 kLUT**)  — AXI4-style burst DMA stub. 128-bit, depth-16 R/W FIFOs, 4-state FSM.
- `outer_loop_ctrl.sv`  (**+2-3 kLUT**)  — Multi-tile iterator. Double-buffered weight prefetch. Iterates (L, H, N, D).
- `multi_head_attn.sv`  (**+0 or +87 kLUT**) — H-way parallel attention. `H_PARALLEL=1` instantiates H parallel `attention_head` engines.
- `head_concat_unit.sv` (**+3 kLUT**)    — Registered per-head concat + sum-reduce.

### 1.4 Integration

- `boostvit_controller.sv` — **32-state master FSM** (v2: real residual, full LN, sm_unit wired, lp_wr_cnt capture).
- `boostvit_accelerator.sv`— v2 top — integrates all v2 blocks.
- `boostvit_top.sv`        — v1 synthesis wrapper (44 kLUT, attention-only). *Not needed for the v2 build.*
- `boostvit_full_top.sv`   — v1 intermediate wrapper. *Not needed for the v2 build.*

### 1.5 Testbenches

- `tb_exp_accuracy.sv`         — Exhaustive expcalc_v2 accuracy.
- `tb_log_accuracy.sv`         — Exhaustive logcalc_v2 accuracy.
- `tb_bspe_tile_cycles.sv`     — BSPE 16×16 tile cycle count.
- `tb_boostvit_accuracy.sv`    — Booth skip rate + softmax error panel (paper Table I patterns).
- `tb_boostvit_top.sv`         — Wrapper smoke test.
- `tb_vit_all_models.sv`       — TOY / Tiny / Small / Base end-to-end outputs.
- `tb_boostvit_accelerator.sv` — v2 full accelerator — 32-state trace + observability.

---

## 2. v2 fixes (closing the three DCE holes in v1)

### 2.1 Real residual adder
v1 hardcoded `res_b = 128'd0`, so `residual_add_16` collapsed to a
wire. v2 adds a **second read bus** (`buf_ren_b / buf_sel_b /
buf_raddr_b / buf_rdata_b`) through the controller. In `S_RES1` /
`S_RES2` the controller reads two operands from two different buffers
simultaneously, avoiding same-RAM triple-port conflicts:

- `S_RES1`: port A = `act_buf[cnt]` (X), port B = `scratch[160+cnt]` (W_O output). Write `out_buf[16+cnt-1]`.
- `S_RES2`: port A = `out_buf[16+cnt]` (residual_1), port B = `scratch[128+cnt]` (MLP2 output). Write `out_buf[48+cnt-1]`.

MLP2 and W_O outputs were rerouted to **scratch_buf** specifically to
free `out_buf` for the residual write-back side.

### 2.2 Full 16-token LayerNorm
v1 drove only `ln_x_in[0 +: 128]` (one token), pruning 15 of 16 LN
instances. v2 adds a **2048-bit shadow register** `ln_batch_reg` that
is sequentially filled in `S_LN1_LOAD` / `S_LN2_LOAD` (one token per
cycle), then the whole 16-token batch drives `ln_array_16x16` in
parallel. This matches the paper's sequential mean–variance–normalize
LayerNorm operating on a 16-token batch register. Output `ln_y_out` is
latched into `ln_y_latched` and written back token-by-token in
`S_LN1_STORE` / `S_LN2_STORE`.

### 2.3 SM Unit observability
`sm_unit` outputs weren't consumed anywhere in v1. v2 adds a new
`host_out_addr[11:4]` decode range that exposes four SM Unit debug
registers directly to the host read port (see §3).

### 2.4 BRAM-latency off-by-1 (LOAD + STREAM)
v1 asserted `lp_load_cols[cnt]` / `lp_valid_x` on the same cycle the
BRAM read was issued, so the first weight column / activation slot
received stale data. v2 extends every LOAD and STREAM state from 16
to 17 cycles and gates the signal on `cnt >= 1` with index `cnt - 1`.
Same fix applied to `S_QK_K_LOAD`.

### 2.5 lp_wr_cnt (capture-side)
The `LP_DRAIN=12` gate in `_CAP` states was wrong — `lp_out_valid`
fires during `cnt = 0..12`, not `cnt = 12..27`. v2 uses a registered
write counter `lp_wr_cnt` incrementing on every `lp_out_valid` pulse
inside any CAPTURE state.

---

## 3. Observability address map

`host_out_addr[11:4]` decodes a debug range (0xF0..0xFA) that anchors
every major block's internal state to a LUT-consuming output:

| host_out_addr[11:4] | Value returned |
|---|---|
| `0xF0` | `smu_e_out` (per-element exp, Q1.7) |
| `0xF1` | `smu_sm_out` (softmax result) |
| `0xF2` | `smu_lsm_out` (log-softmax, Q3.5 — the LOGOS output format) |
| `0xF3` | `{116'd0, smu_es_sum}` (sum of exp, 12-bit; max 4080) |
| `0xF4` | `wide_accum y_out` |
| `0xF5` | `wide_accum dbg[0..127]` |
| `0xF6` | `head_concat sum-reduce` |
| `0xF7` | `head_concat all_heads_reg[127:0]` |
| `0xF8` | `{layer, head, n_tile, d_tile, state, total_cycles}` |
| `0xF9` | `{total_tiles_fired, 96'd0}` |
| `0xFA` | `{axi_busy, axi_done, 126'd0}` |
| else   | `out_buf[host_out_addr]` (normal output read) |

Addresses 0x000..0x3FF are normal output-buffer reads (4 KB window).

---

## 4. Multi-head configuration

```
boostvit_accelerator #(
    .H_HEADS   (3),
    .H_PARALLEL(1),
    .BUF_DEPTH (4096),
    .BUF_ADDR_W(12)
) u_accel ( ... );
```

With `H_PARALLEL = 1`:

- DeiT-Tiny  (D=192, H=3,  N=196, L=12): ~+87 kLUT  (on top of 89.5 kLUT v1 baseline) — **paper target config**
- DeiT-Small (H=6):  ~+170 kLUT
- DeiT-Base  (H=12): ~+340 kLUT (exceeds the XCZU7EV ~230 kLUT budget)

The LOGOS paper targets **DeiT-Tiny (D=192, H=3, N=196, L=12)**; larger DeiT
variants are reachable by re-parameterising the top level but do not fit
the ZCU104 fully parallel.

---

## 5. Expected synthesis results (Vivado 2024.1, ZCU104 / XCZU7EV)

Projected from v1's confirmed 89.5 kLUT measurement (estimates, not post-synthesis numbers):

| Block                          | v1 LUT | v2 LUT (est) | Notes |
|---|---|---|---|
| `u_ah` (attention_head single) | 43,261 | 43,261     | unchanged |
| `u_lp` (linear_proj)           | 43,553 | 43,553     | unchanged |
| `u_ctl` (controller)           | 2,722  | ~5,000     | 32 states, dual-port read bus, lp_wr_cnt, ln_batch_reg |
| `u_ln` (ln_array_16x16)        | ~0     | ~5,000     | all 16 LN instances live |
| `u_sm_unit`                    | ~0     | ~3,000     | outputs observable (paper's standalone LOGOS engine: 1,917 LUT) |
| `u_res` (residual_add_16)      | ~0     | ~200       | `res_b` now wired |
| `u_gelu`                       | ~0     | ~200       | already combinational |
| `u_mha` (multi_head_attn H=3)  | —      | ~87,000    | 3 parallel attention_heads |
| `u_hc` (head_concat_unit)      | —      | ~3,000     | registered per-head fanout |
| `u_accum` (wide_accum_bank)    | —      | ~10,000    | 16× 24-bit accumulators |
| `u_axi` (axi_burst_if)         | —      | ~7,000     | AXI burst stub + 2× FIFO16×128 |
| `u_olc` (outer_loop_ctrl)      | —      | ~3,000     | multi-tile iterator |
| **Total projected**            | 89,537 | **≈210,000** | LOGOS paper "This Work": 207,300 |

If the multi-tile log-domain merge stage (§0.2) is added, expect a small
increment (a correction LUT, a max/subtract and per-row partial-sum
storage); it should stay within the paper's 1,917-LUT engine scale but is
not yet reflected above.

- **BRAM:** 4× `ram_dp` (4096×128) ≈ 4 × 16 BRAM36 ≈ 64 BRAM36, plus 2× FIFO16×128
  (typically LUTRAM, ≤ 4 BRAM36 if mapped to BRAM). Paper reports **58 BRAM**.
  *The earlier "128 BRAM36 for 4 RAMs" figure was an over-estimate; confirm from the
  post-synthesis utilisation report.*
- **DSP:** 0 by design — Booth-Serial Skipping PE and the LOGOS exp/log units use no DSP
  (paper: 0 DSP).

---

## 6. Build / simulate

### 6.1 Icarus Verilog (reproduces in ~1 second)

```
iverilog -g2012 -o accel2 \
    BSPE.sv Boothencoder.sv Boothmul.sv Boothunit.sv Fifo.sv \
    exp_cal.sv logcalc_v2.sv softmax_from_exp_16.sv softmax_16.sv \
    layer_norm_16.sv systolic16.v systolic_16x16_softmax.sv \
    linear_proj.sv attention_head.sv gelu_approx_16.sv \
    residual_add_16.sv ln_array_16x16.sv ram_dp.sv sm_unit.sv \
    wide_accum_bank.sv axi_burst_if.sv outer_loop_ctrl.sv \
    multi_head_attn.sv head_concat_unit.sv \
    boostvit_controller.sv boostvit_accelerator.sv \
    tb_boostvit_accelerator.sv
vvp accel2
```

### 6.2 Vivado synthesis

1. Create a new ZCU104 project (XCZU7EV-FFVC1156-2-E).
2. Add the 26 RTL sources listed in §6.1 (everything except testbenches and the
   v1 wrappers `boostvit_top.sv` / `boostvit_full_top.sv`, to avoid multiple tops).
3. Set top: `boostvit_accelerator`.
4. Parameters: `H_HEADS=3`, `H_PARALLEL=1`, `BUF_DEPTH=4096`, `BUF_ADDR_W=12`.
5. Run synthesis.
6. Report utilisation → expect ~210 kLUT, 0 DSP, ~60 BRAM (paper: 207.3 kLUT / 0 / 58).

**Bonded IOB note:** the v2 top has ~480 physical pins from the host +
DRAM interfaces, which exceeds the board's user I/O budget and will fail
P&R. For actual board deployment wrap in AXI4-Lite / AXI4. For
**synthesis-only LUT reporting this does not matter.**

---

## 7. Test results summary

All seven testbenches pass on the final sources:

- `tb_exp_accuracy`:       Max 1.00 ULP, Mean **0.186 ULP** (paper: 0.186 profiled; 0.31 before LUT profiling).
- `tb_log_accuracy`:       Max 1.00 ULP, Mean **0.286 ULP** (paper: 0.286).
- `tb_bspe_tile_cycles`:   **33 cycles** per 16×16 attention tile (paper ~50).
- `tb_boostvit_accuracy`:  Skip rate natural **30.5%**, LSB-scaled **35.4%**.
- `tb_boostvit_top`:       softmax sum = **128/128** (exact 1.0 in Q1.7).
- `tb_vit_all_models`:     TOY + Tiny + Small + Base all clean non-X.
- `tb_boostvit_accelerator`: All 32 FSM states exercised; outer loop `all_done=1`; SM Unit readback returns real data (`e_out=0x4d58..2f`, `sm_out=0x0809..05`, `es_sum=0x4e5`); residual chain active.

### 7.1 Paper-reported softmax accuracy (LOGOS Table I) — reference targets

`tb_boostvit_accuracy`'s softmax error panel should be compared against:

| Pattern | Mean error | Max error |
|---|---|---|
| Uniform | 0.86% | 0.86% |
| Dominant winner | 0.23% | 3.12% |
| ViT 4-tier attention | **1.87%** | 2.36% |
| Sharp-peaked attention | 1.85% | 3.16% |
| Near-uniform attention | 2.01% | 3.06% |

### 7.2 Paper-reported hardware / end-to-end results (reference, not reproduced here)

- LOGOS softmax engine: 1,917 LUT, 0 DSP (FPGA, post-P&R); 12,907 µm², 3.038 ns (~328 MHz) in 45 nm ASIC.
  Standalone exp unit 720 ps, log unit 334 ps.
- DeiT-Tiny on Imagenette:

| Pipeline | Top-1 (%) | Top-5 (%) |
|---|---|---|
| FP32 reference | 79.2 | 99.1 |
| INT8 baseline | 70.76 | 98.12 |
| INT8 + LOGOS | 70.76 | 95.41 |

  Top-1 is preserved; note that top-5 drops by ~2.7 points versus the INT8 baseline.
  This RTL repository does not run Imagenette; these numbers come from the paper's software/co-design flow.

---

## 8. Cycle-count extrapolation

From `tb_boostvit_accelerator`: single-tile inner block **= 588 cycles**.

| Model | cycles/block | cycles/model (L=12) | @ 500 MHz | @ ~328 MHz (paper LOGOS engine fmax) |
|---|---|---|---|---|
| TOY (N=16, D=16, H=1) | 588 | 7,056 | 0.014 ms | 0.022 ms |
| DeiT-Tiny (N=196, D=192, H=3) | 240,292 | 2,883,504 | 5.77 ms (173 FPS) | 8.79 ms (~114 FPS) |
| DeiT-Small (N=196, D=384, H=6) | 480,532 | 5,766,384 | 11.53 ms | 17.58 ms |
| DeiT-Base (N=196, D=768, H=12) | 961,012 | 11,532,144 | 23.06 ms | 35.16 ms |

Notes:

- The earlier README listed TOY as 5,856 cycles/model, which does not equal 588 × 12;
  7,056 is used here assuming L=12 (re-check the TOY testbench's layer count).
- Throughput vs. the paper's 852.1 GOPs: DeiT-Tiny is roughly 1.3 GMACs (~2.5 GOP) per image,
  so 173 FPS corresponds to ~0.43 TOPS (≈0.29 TOPS at 114 FPS) under a plain op count.
  The previous statement that the throughput "tracks the paper's 853 GOPs within noise" is **not**
  supported by these cycle counts. Reaching the paper's figure requires either a different
  op-counting convention (e.g. crediting skipped Booth digits as effective operations) or additional
  parallelism/overlap; define the GOPs convention before comparing.
- The 500 MHz column is aspirational: the paper's complete softmax engine closes at 3.038 ns,
  and the BSPE Booth + residual adder path is the known retiming concern (§10).

---

## 9. Mandates preserved

- LUT-based `expcalc_v2` / `logcalc_v2` are **unchanged bit-for-bit**.
- **No Taylor expansions** anywhere (LOGOS replaces ReHIT-style Taylor/iterative schemes with
  profiled LUTs + shift-add).
- Systolic array with **row-end expcalc + softmax-at-end** preserved.
- Non-attention matmuls use **raw systolic_16x16** via linear_proj.
- **Booth-Serial Skipping PE** (`BSPE.sv`) unchanged.
- Two-array design (attention + linear_proj) accepted.

---

## 10. Next steps (if going past paper parity)

1. **Add the multi-tile log-domain softmax merge** (§0.2): per-row `ln S` partial sums and the
   `ln(1 + e^−|Δ|)` correction LUT in `sm_unit`, so full 196-token rows are normalised across
   13 tiles rather than per tile.
2. Verify the exp LUT / 1/ln2 constant, widened row-sum log unit, and GELU spec against the paper (§0.2).
3. Decide whether `attention_head` should consume Q3.5 log-softmax (paper) or linear Q1.7 softmax (current testbench).
4. Wrap the 128-bit host interface in AXI4-Lite for on-board deployment.
5. Replace DRAM stub with an actual DDR4 interface via Vivado MIG.
6. Add cycle-accurate pipelined handshake on AXI R/W (currently depth-1 outstanding).
7. Re-timing closure toward 328–500 MHz (critical path: BSPE Booth + residual adder).
8. Post-synthesis: replace the §5 estimates (LUT, BRAM) with measured utilisation.

---

## 11. Revision notes (this README update)

Changes made after reading the LOGOS paper:

- Retitled for BoostViT + LOGOS; target board corrected to **ZCU104 (XCZU7EV)**.
- Reference targets changed from "Paper Table III" (BoostViT-only numbers) to the LOGOS
  Table II rows: this work 207.3 kLUT / 0 DSP / 58 BRAM / 852.1 GOPs.
- Added §0 (block mapping, algorithm summary, alignment status) and §7.1–7.2 (paper accuracy/hardware references).
- Fixed exp accuracy reference ("0.93/0.31" → 0.186 profiled, 0.31 pre-profiling).
- BRAM estimate revised from ~132 to ~60 (4 × 4096×128 RAMs ≈ 64 BRAM36; paper 58).
- Frequency/throughput section now includes ~328 MHz and drops the unsupported "tracks 853 GOPs" claim;
  TOY cycle count corrected to 588 × 12 = 7,056.
- File counts corrected (35 files; 26 RTL files needed for the v2 build).
- Flagged the multi-tile log-domain merge as an unimplemented gap.

— End README —
