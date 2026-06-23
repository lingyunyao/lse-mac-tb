# lse-mac-tb

Self-contained Verilator testbench for the **log-domain MAC unit** (multiply–accumulate
in the −log₂(*p*) probability domain) — the LSE arithmetic block described in
[Yao et al., IEEE TCAS-I 2025](https://ieeexplore.ieee.org/document/11185227).

## Math background

Probabilities are stored as **−log₂(*p*)** in 24-bit fixed-point
(14 integer + 10 fractional bits). Three identities drive the whole datapath:

| Operation | Linear domain | Log domain (this code) |
|-----------|--------------|------------------------|
| Multiply  | *p* × *q*    | −log₂(*p*) + (−log₂(*q*)) — just addition |
| Add (LSE) | *p* + *q*    | min(*a*, *b*) − log₂(1 + 2^−\|*a*−*b*\|) — log-sum-exp |
| Zero      | *p* = 0      | sentinel `24'h0C3500` (= 800 000 decimal) |

`lse_mult` implements the multiply identity (plain adder with zero-sentinel
absorption). `lse_add` implements the add identity using a 16-entry LUT for
the correction term log₂(1 + 2^−|Δ|), with linear interpolation between
adjacent entries.

`mac_unit` chains them: `acc_out = lse_add(acc_in, lse_mult(w, x))`.

### Fixed-point encoding

```
Bit width : 24 bits (signed 2's complement)
Format    : Q14.10  →  1 ULP = 2^−10 ≈ 0.001 in −log₂
Sentinel  : 24'd800000  →  p = 0  (−log₂(0) = ∞)
Example   : 1024 = 1.0 in −log₂  →  p = 2^−1 = 0.5
```

## Files

| File | Description |
|------|-------------|
| `tb_mac.sv` | All modules + testbench in one file (no external dependencies) |
| `Makefile`  | Compile + run with Verilator |

## Prerequisites

**Verilator ≥ 5.0** is required for `--timing` support. The system package on
Ubuntu 22.04 and earlier is too old; install a current version via one of:

```bash
# macOS
brew install verilator

# Linux / macOS — via conda-forge
conda install -c conda-forge verilator

# Linux — from source (https://verilator.org/guide/latest/install.html)
```

Verify the version:

```bash
verilator --version   # must print 5.x or higher
```

## Quick start

```bash
git clone https://github.com/lingyunyao/lse-mac-tb.git
cd lse-mac-tb
make
```

Expected output:

```
=== tb_mac  (24-bit -log2 fixed-point, tol=2 ULP) ===

-- lse_mult --
  ok    mult(0,0) = 0                     got=0       exp=0
  ok    mult(1k,1k) = 2k                  got=2048    exp=2048
  ok    mult(-inf,x) = -inf               got=800000  exp=800000
  ok    mult(x,-inf) = -inf               got=800000  exp=800000

-- lse_add --
  ok    add(-inf, 2048) = 2048            got=2048    exp=2048
  ok    add(-inf, 0) = 0                  got=0       exp=0
  ok    add(2048,2048) = 1024             got=1024    exp=1024
  ok    add(1024,2048) ~ 426              got=426     exp=426
  ok    add(2048,1024) ~ 426              got=426     exp=426

-- MAC accumulation (3 steps) --
  ok    acc after step 1                  got=1024    exp=1024
  ok    acc after step 2                  got=426     exp=426
  ok    acc after step 3 (~197 ULP)       got=198     exp=198

=== 12 passed, 0 failed ===
RESULT: PASS
```

If Verilator is not on `PATH`, pass it explicitly:

```bash
make VERILATOR=/path/to/verilator
```

### Without make

```bash
verilator --binary --top-module tb_mac --timing -sv \
  -Wno-fatal --Mdir obj_dir tb_mac.sv \
  && ./obj_dir/Vtb_mac
```

## Test descriptions

| Group | Test | What it checks |
|-------|------|----------------|
| `lse_mult` | `mult(0, 0) = 0` | Identity: −log₂(1×1) = 0 |
| `lse_mult` | `mult(1024, 1024) = 2048` | −log₂(0.5×0.5) = 2.0 |
| `lse_mult` | `mult(-inf, x) = -inf` | Zero-sentinel absorption (left) |
| `lse_mult` | `mult(x, -inf) = -inf` | Zero-sentinel absorption (right) |
| `lse_add`  | `add(-inf, 2048) = 2048` | Identity: LSE(0, p) = p |
| `lse_add`  | `add(-inf, 0) = 0` | Identity at p=1 |
| `lse_add`  | `add(2048, 2048) = 1024` | −log₂(0.25+0.25) = 1.0 (exact) |
| `lse_add`  | `add(1024, 2048) ≈ 426` | −log₂(0.5+0.25) = −log₂(0.75) ≈ 0.415 |
| `lse_add`  | `add(2048, 1024) ≈ 426` | Symmetry of log-sum-exp |
| MAC step 1 | `acc = lse_add(−∞, 1024) = 1024` | Accumulator cold-start |
| MAC step 2 | `acc = lse_add(1024, 2048) ≈ 426` | Two-term accumulation |
| MAC step 3 | `acc = lse_add(426, 3072) ≈ 198` | −log₂(0.5+0.25+0.125) = −log₂(0.875) ≈ 0.193 |

Tolerance is **2 ULP** for `lse_add` results (LUT quantisation error);
`lse_mult` results are exact.

## Parameters

Defined as `localparam` in `tb_mac` and as module `parameter`s in `lse_add`:

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `INT_BITS` | 14 | Integer bits in Q*m*.*n* format |
| `FRAC_BITS` | 10 | Fractional bits |
| `LUT_SIZE` | 16 | Number of LUT entries for LSE correction |
| `LUT_PREC` | 10 | Bit-width of each LUT entry |
| `TOL` | 2 | Acceptance tolerance in ULP |

To change tolerance, edit the `localparam TOL = 2;` line in `tb_mac.sv`.

## Citation

If this testbench or the underlying arithmetic is useful for your work, please cite:

```bibtex
@article{yao2025logsumexp,
  title     = {LogSumExp: Efficient Approximate Logarithm Acceleration for Embedded Tractable Probabilistic Reasoning},
  author    = {Yao, Lingyun and Zhao, Shirui and Trapp, Martin and Leslin, Jelin and Verhelst, Marian and Andraud, Martin},
  journal   = {IEEE Transactions on Circuits and Systems I: Regular Papers},
  year      = {2025},
  publisher = {IEEE},
  url       = {https://ieeexplore.ieee.org/document/11185227}
}
```

## License

MIT
