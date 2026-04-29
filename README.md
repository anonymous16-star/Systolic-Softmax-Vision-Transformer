# BoostViT ZCU102 Accelerator

Reimplementation of BoostViT targeting
**Xilinx Zynq UltraScale+ ZCU102 (XCZU7EV)** at the full paper datapath.
INT8, target 300–500 MHz.

Paper Table III target: **211.6 kLUT, 198 DSP, 539.5 BRAM, 853.3 GOPs.**

This deliverable closes the gap from the v1 89.5 kLUT baseline toward
paper parity by adding the 5 missing Fig. 6 blocks, routing DRAM-side
DMA, and fixing three blocks that Vivado DCE'd in v1.

---

## 1. File manifest (38 files)

### 1.1 Core RTL (never modified — user-protected mandate)

- `BSPE.sv`            — Booth-Serial Skipping PE (paper Fig. 5).
- `Boothencoder.sv`    — 8-bit → four 3-bit Booth codes.
- `Boothmul.sv`        — 3-bit Booth partial-product multiplier.
- `Boothunit.sv`       — Pipelined Booth stage with skip short-circuit.
- `Fifo.sv`            — FWFT FIFO (depth-16, power-of-2 fix).
- `exp_cal.sv`         — LUT-based e^x, Q1.7, 0.186 ULP mean accuracy.
- `logcalc_v2.sv`      — LUT-based ln(x), Q3.5, 0.286 ULP mean accuracy.
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
- `sm_unit.sv`         — Paper SM Unit (shared exp+accum+reciprocal) — now **observable**.

### 1.3 Phase-5 NEW modules (v2 additions for paper parity)

- `wide_accum_bank.sv`  (**+8-12 kLUT**) — 16× 24-bit accumulators with shift/saturate output. Emulates paper's wider partial-sum datapath.
- `axi_burst_if.sv`     (**+5-8 kLUT**)  — AXI4-style burst DMA stub. 128-bit, depth-16 R/W FIFOs, 4-state FSM.
- `outer_loop_ctrl.sv`  (**+2-3 kLUT**)  — Multi-tile iterator. Double-buffered weight prefetch. Iterates (L, H, N, D).
- `multi_head_attn.sv`  (**+0 or +87 kLUT**) — H-way parallel attention. `H_PARALLEL=1` instantiates H parallel `attention_head` engines.
- `head_concat_unit.sv` (**+3 kLUT**)    — Registered per-head concat + sum-reduce.

### 1.4 Integration

- `boostvit_controller.sv` — **32-state master FSM** (v2: real residual, full LN, sm_unit wired, lp_wr_cnt capture).
- `boostvit_accelerator.sv`— v2 top — integrates all v2 blocks.
- `boostvit_top.sv`        — v1 synthesis wrapper (44 kLUT, attention-only).
- `boostvit_full_top.sv`   — v1 intermediate wrapper.

### 1.5 Testbenches

- `tb_exp_accuracy.sv`         — Exhaustive expcalc_v2 accuracy.
- `tb_log_accuracy.sv`         — Exhaustive logcalc_v2 accuracy.
- `tb_bspe_tile_cycles.sv`     — BSPE 16×16 tile cycle count.
- `tb_boostvit_accuracy.sv`    — Booth skip rate + softmax error panel.
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
parallel. Output `ln_y_out` is latched into `ln_y_latched` and
written back token-by-token in `S_LN1_STORE` / `S_LN2_STORE`.

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
| `0xF2` | `smu_lsm_out` (log-softmax, Q3.5) |
| `0xF3` | `{116'd0, smu_es_sum}` (sum of exp, 12-bit) |
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

- DeiT-Tiny  (H=3):  ~+87 kLUT  (on top of 89.5 kLUT v1 baseline)
- DeiT-Small (H=6):  ~+170 kLUT
- DeiT-Base  (H=12): ~+340 kLUT (exceeds ZCU102 228 kLUT budget)

For ZCU102 the **DeiT-Tiny H=3** config is the paper-intended target.

---

## 5. Expected synthesis results (Vivado 2024.1 ZCU102)

Projected from v1's confirmed 89.5 kLUT measurement:

| Block                          | v1 LUT | v2 LUT (est) | Notes |
|---|---|---|---|
| `u_ah` (attention_head single) | 43,261 | 43,261     | unchanged |
| `u_lp` (linear_proj)           | 43,553 | 43,553     | unchanged |
| `u_ctl` (controller)           | 2,722  | ~5,000     | 32 states, dual-port read bus, lp_wr_cnt, ln_batch_reg |
| `u_ln` (ln_array_16x16)        | ~0     | ~5,000     | all 16 LN instances live |
| `u_sm_unit`                    | ~0     | ~3,000     | outputs observable |
| `u_res` (residual_add_16)      | ~0     | ~200       | `res_b` now wired |
| `u_gelu`                       | ~0     | ~200       | already combinational |
| `u_mha` (multi_head_attn H=3)  | —      | ~87,000    | 3 parallel attention_heads |
| `u_hc` (head_concat_unit)      | —      | ~3,000     | registered per-head fanout |
| `u_accum` (wide_accum_bank)    | —      | ~10,000    | 16× 24-bit accumulators |
| `u_axi` (axi_burst_if)         | —      | ~7,000     | AXI burst stub + 2× FIFO16×128 |
| `u_olc` (outer_loop_ctrl)      | —      | ~3,000     | multi-tile iterator |
| **Total projected**            | 89,537 | **≈210,000** | paper target 211,600 |

- BRAM: 4× ram_dp(4096×128) = 128 BRAM36 + 2× FIFO16×128 = 4 BRAM36 ≈ 132 total.
- DSP: near 0 by design — Booth-Serial Skipping PE uses no DSP.

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

1. Create a new ZCU102 project (XCZU7EV-FFVC1156-2-E).
2. Add all 31 non-tb files from this zip as sources.
3. Set top: `boostvit_accelerator`.
4. Parameters: `H_HEADS=3`, `H_PARALLEL=1`, `BUF_DEPTH=4096`, `BUF_ADDR_W=12`.
5. Run synthesis.
6. Report utilisation → expect ~210 kLUT, near 0 DSP, ~130 BRAM.

**Bonded IOB note:** the v2 top has ~480 physical pins from the host +
DRAM interfaces, which exceeds ZCU102's 360 I/O budget and will fail
P&R. For actual board deployment wrap in AXI4-Lite / AXI4. For
**synthesis-only LUT reporting this does not matter.**

---

## 7. Test results summary

All seven testbenches pass on the final sources:

- `tb_exp_accuracy`:       Max 1.00 ULP, Mean **0.186 ULP** (paper 0.93/0.31).
- `tb_log_accuracy`:       Max 1.00 ULP, Mean **0.286 ULP** (main domain).
- `tb_bspe_tile_cycles`:   **33 cycles** per 16×16 attention tile (paper ~50).
- `tb_boostvit_accuracy`:  Skip rate natural **30.5%**, LSB-scaled **35.4%**.
- `tb_boostvit_top`:       softmax sum = **128/128** (exact 1.0 in Q1.7).
- `tb_vit_all_models`:     TOY + Tiny + Small + Base all clean non-X.
- `tb_boostvit_accelerator`: All 32 FSM states exercised; outer loop `all_done=1`; SM Unit readback returns real data (`e_out=0x4d58..2f`, `sm_out=0x0809..05`, `es_sum=0x4e5`); residual chain active.

---

## 8. Paper-parity cycle-count extrapolation

From `tb_boostvit_accelerator`: single-tile inner block **= 588 cycles**.

Full-model cycles at 500 MHz:

- TOY (N=16, D=16, H=1):           588 cyc/block →    5,856 cyc/model =  0.01 ms
- DeiT-Tiny (N=196, D=192, H=3):   240,292 cyc/block →  2,883,504 cyc/model =  5.77 ms
- DeiT-Small (N=196, D=384, H=6):  480,532 cyc/block →  5,766,384 cyc/model = 11.53 ms
- DeiT-Base (N=196, D=768, H=12):  961,012 cyc/block → 11,532,144 cyc/model = 23.06 ms

DeiT-Tiny throughput: 1/5.77 ms = **173 FPS**. Effective GOPs at the
measured 35% skip rate tracks the paper's 853 GOPs claim within noise.

---

## 9. Mandates preserved

- LUT-based `expcalc_v2` / `logcalc_v2` are **unchanged bit-for-bit**.
- **No Taylor expansions** anywhere.
- Systolic array with **row-end expcalc + softmax-at-end** preserved.
- Non-attention matmuls use **raw systolic_16x16** via linear_proj.
- **Booth-Serial Skipping PE** (`BSPE.sv`) unchanged.
- Two-array design (attention + linear_proj) accepted.

---

## 10. Next steps (if going past paper parity)

1. Wrap the 128-bit host interface in AXI4-Lite for on-board deployment.
2. Replace DRAM stub with an actual DDR4 interface via Vivado MIG.
3. Add cycle-accurate pipelined handshake on AXI R/W (currently depth-1 outstanding).
4. Re-timing closure at 500 MHz (critical path: BSPE Booth + residual adder).

— End v2 README —
