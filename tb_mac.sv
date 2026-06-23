// Self-contained testbench for the log-domain MAC unit.
// Packs lse_mult, lse_add, and mac_unit together with the testbench
// so the file compiles standalone without the full RTL tree.
//
// Run:
//   make compile_mac run_mac   (from tb/)
//
// Fixed-point encoding: 14 integer + 10 fractional bits, -log2(p).
//   1 ULP = 2^-10 ≈ 0.001 in -log2 ≈ 0.07% probability change.
//   800000 is the -infinity sentinel (p = 0).

// -----------------------------------------------------------------------
// lse_mult: log-domain multiply = plain add in -log2 space.
// -----------------------------------------------------------------------
module lse_mult (
  input  logic [23:0] in0,
  input  logic [23:0] in1,
  output logic [23:0] result
);
  always_comb begin
    if (in0 == 24'd800000 || in1 == 24'd800000)
      result = 24'd800000;
    else
      result = in0 + in1;
  end
endmodule

// -----------------------------------------------------------------------
// lse_add: log-domain add = log-sum-exp with LUT error correction.
// -----------------------------------------------------------------------
module lse_add #(
  parameter INT_BITS  = 14,
  parameter FRAC_BITS = 10,
  parameter LUT_SIZE  = 16,
  parameter LUT_PREC  = 10
)(
  input  logic [INT_BITS+FRAC_BITS-1:0] in0,
  input  logic [INT_BITS+FRAC_BITS-1:0] in1,
  input  logic [LUT_PREC-1:0]           lut_registers[LUT_SIZE],
  output logic [INT_BITS+FRAC_BITS-1:0] result
);
  localparam LUT_BITS = $clog2(LUT_SIZE);

  logic signed [INT_BITS+FRAC_BITS-1:0]   mx, mi, y, My, Mz, Mz_shifted;
  logic signed [INT_BITS-1:0]             Ey;
  logic signed [FRAC_BITS-1:0]            ec, next_ec, interp, final_ec;
  logic        [FRAC_BITS-LUT_BITS-1:0]   Mz_key_resid;
  logic        [LUT_BITS-1:0]             lut_key;
  logic        [LUT_PREC-1:0]             lut[2];
  logic signed [2*FRAC_BITS-LUT_BITS-1:0] interp_temp;

  assign lut[0] = lut_registers[lut_key];
  assign lut[1] = lut_registers[lut_key+1];

  always_comb begin
    mx           = (in0 > in1) ? in0 : in1;
    mi           = (in0 < in1) ? in0 : in1;
    y            = mi - mx;
    Ey           = y[INT_BITS+FRAC_BITS-1:FRAC_BITS];
    My           = y[FRAC_BITS-1:0];
    Mz           = (1 <<< FRAC_BITS) + My;
    Mz_shifted   = Mz >>> -Ey;

    lut_key      = Mz_shifted[FRAC_BITS-1:FRAC_BITS-LUT_BITS];
    Mz_key_resid = Mz_shifted[FRAC_BITS-LUT_BITS-1:0];
    ec           = lut[0];
    next_ec      = (&lut_key) ? lut[0] : lut[1];
    interp_temp  = (next_ec - ec) * Mz_key_resid;
    interp       = interp_temp >>> (FRAC_BITS-LUT_BITS);
    final_ec     = ec + interp;

    if (in0 == 24'd800000)
      result = in1;
    else if (in1 == 24'd800000)
      result = in0;
    else
      result = mi - Mz_shifted - {{INT_BITS{final_ec[FRAC_BITS-1]}}, final_ec};
  end
endmodule

// -----------------------------------------------------------------------
// mac_unit: one log-domain MAC step (combinational).
//   acc_out = lse_add(acc_in, lse_mult(w, x))
// -----------------------------------------------------------------------
module mac_unit #(
  parameter LUT_SIZE = 16,
  parameter LUT_PREC = 10
)(
  input  logic [23:0]         w,
  input  logic [23:0]         x,
  input  logic [23:0]         acc_in,
  input  logic [LUT_PREC-1:0] lut_regs[LUT_SIZE],
  output logic [23:0]         prod,
  output logic [23:0]         acc_out
);
  lse_mult u_mult (.in0(w),      .in1(x),    .result(prod));
  lse_add  u_add  (.in0(acc_in), .in1(prod), .lut_registers(lut_regs), .result(acc_out));
endmodule

// -----------------------------------------------------------------------
// tb_mac
// -----------------------------------------------------------------------
module tb_mac;

  localparam LUT_SIZE = 16;
  localparam LUT_PREC = 10;
  localparam TOL      = 2;   // ULP tolerance for lse_add rounding

  logic [LUT_PREC-1:0] lut_regs[LUT_SIZE];
  logic [23:0] w, x, acc_in, prod, acc_out;

  int pass_cnt, fail_cnt;

  mac_unit #(.LUT_SIZE(LUT_SIZE), .LUT_PREC(LUT_PREC)) dut (.*);

  task automatic check(input int got, exp, input string label);
    automatic int diff = (got > exp) ? got - exp : exp - got;
    if (diff <= TOL) begin
      pass_cnt++;
      $display("  ok    %-32s  got=%-6d  exp=%0d", label, got, exp);
    end else begin
      fail_cnt++;
      $display("  FAIL  %-32s  got=%-6d  exp=%0d  diff=%0d", label, got, exp, diff);
    end
  endtask

  initial begin
    pass_cnt = 0; fail_cnt = 0;

    // Silicon LUT (error-correction table; see sim_top.sv for source)
    lut_regs[0]  = 10'd0;
    lut_regs[1]  = 10'd25;
    lut_regs[2]  = 10'd45;
    lut_regs[3]  = 10'd48;
    lut_regs[4]  = 10'd73;
    lut_regs[5]  = 10'd64;
    lut_regs[6]  = 10'd63;
    lut_regs[7]  = 10'd70;
    lut_regs[8]  = 10'd86;
    lut_regs[9]  = 10'd66;
    lut_regs[10] = 10'd49;
    lut_regs[11] = 10'd34;
    lut_regs[12] = 10'd22;
    lut_regs[13] = 10'd12;
    lut_regs[14] = 10'd5;
    lut_regs[15] = 10'd1;

    $display("=== tb_mac  (24-bit -log2 fixed-point, tol=%0d ULP) ===", TOL);

    // ----------------------------------------------------------------
    // lse_mult: log-domain multiply = add in -log2 space
    // ----------------------------------------------------------------
    $display("\n-- lse_mult --");
    acc_in = 24'd800000;  // hold acc_in at -inf so acc_out doesn't obscure prod

    w = 0;          x = 0;          #1; check(prod, 0,        "mult(0,0) = 0");
    w = 1024;       x = 1024;       #1; check(prod, 2048,     "mult(1k,1k) = 2k");
    w = 24'd800000; x = 1024;       #1; check(prod, 800000,   "mult(-inf,x) = -inf");
    w = 1024;       x = 24'd800000; #1; check(prod, 800000,   "mult(x,-inf) = -inf");

    // ----------------------------------------------------------------
    // lse_add: log-sum-exp
    // ----------------------------------------------------------------
    // Drive through mac_unit with x=0 so prod=w (lse_mult(w,0)=w).
    $display("\n-- lse_add --");
    x = 0;

    // Identity: add(-inf, x) = x
    w = 2048; acc_in = 24'd800000; #1; check(acc_out, 2048, "add(-inf, 2048) = 2048");
    w = 0;    acc_in = 24'd800000; #1; check(acc_out, 0,    "add(-inf, 0) = 0");

    // Equal inputs: add(a, a) = a - log2(2) = a - 1024
    //   add(2048,2048): -log2(0.25+0.25) = 1.0 -> 1024 ULP
    w = 2048; acc_in = 2048; #1; check(acc_out, 1024, "add(2048,2048) = 1024");

    // Unequal: add(1024,2048): -log2(0.5+0.25) = -log2(0.75) ~ 425 ULP  [RTL=426]
    w = 2048; acc_in = 1024; #1; check(acc_out, 426, "add(1024,2048) ~ 426");
    w = 1024; acc_in = 2048; #1; check(acc_out, 426, "add(2048,1024) ~ 426");  // symmetric

    // ----------------------------------------------------------------
    // MAC accumulation: acc = lse_add(acc, w_i) for w = 1024, 2048, 3072
    // Expected final: -log2(0.5 + 0.25 + 0.125) = -log2(0.875) ~ 197 ULP
    // ----------------------------------------------------------------
    $display("\n-- MAC accumulation (3 steps) --");
    x = 0;

    acc_in = 24'd800000; w = 1024; #1;  // += p=0.5
    check(acc_out, 1024, "acc after step 1");
    acc_in = acc_out;    w = 2048; #1;  // += p=0.25
    check(acc_out, 426,  "acc after step 2");
    acc_in = acc_out;    w = 3072; #1;  // += p=0.125
    check(acc_out, 198,  "acc after step 3 (~197 ULP)");

    // ----------------------------------------------------------------
    $display("\n=== %0d passed, %0d failed ===", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("RESULT: PASS");
    else               $display("RESULT: FAIL");
    $finish;
  end

endmodule
