/*
 * Copyright (c) 2024, 2025 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_urish_sic1 (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output reg  [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  localparam STATE_HALT = 3'd0;
  localparam STATE_READ_INST = 3'd1;
  localparam STATE_READ_DATA = 3'd2;

  reg [2:0] state;
  reg [7:0] PC;
  wire [7:0] prog_uo_out;
  reg prev_run;

  wire [7:0] A;
  wire [7:0] B;
  wire [7:0] C;
  reg [7:0] prev_A;
  reg [1:0] prev_B_low;
  reg [7:0] reg_C;
  wire [7:0] value_A = A;
  wire [7:0] value_B;
  wire [7:0] result = value_A - value_B;
  wire leq = result[7] || result == 0;  // A <= B if result is negative (sign bit is 1) or zero
  wire halted = state == STATE_HALT;
  wire [7:0] next_PC = halted ? PC : leq ? reg_C : PC + 3;

  reg wr_en;
  reg [7:0] wr_addr;
  reg [7:0] wr_byte;
  reg [7:0] ra_addr;
  reg [7:0] rb_addr;

  wire out_strobe;
  assign uio_out = {3'b0, out_strobe, 2'b0, halted, 1'b0};
  assign uio_oe  = 8'b00010010;

  wire run = uio_in[0];
  wire set_pc = uio_in[2];
  wire set_data = uio_in[3];
  wire [2:0] debug = uio_in[7:5];

  // Debug stuff
  reg [63:0] state_name;
  always @(*) begin
    case (state)
      STATE_HALT: state_name = "Halt";
      STATE_READ_INST: state_name = "RInst";
      STATE_READ_DATA: state_name = "RData";
      default: state_name = "Invalid";
    endcase
  end

  sic1_memory mem (
      .clk  (clk),
      .rst_n(rst_n),

      .wr_en(wr_en),
      .wr_addr(wr_addr),
      .wr_byte(wr_byte),
      .ra_addr(ra_addr[7:2]),
      .rb_addr(rb_addr[7:2]),
      .rb_byte_idx(prev_B_low),
      .rb_byte(value_B),

      .PC_low(state === STATE_READ_DATA ? prev_A[1:0] : PC[1:0]),
      .out_A (A),
      .out_B (B),
      .out_C (C),

      .ui_in(ui_in),
      .uo_out(prog_uo_out),
      .out_strobe(out_strobe)
  );

  always @(*) begin
    case (state)
      STATE_HALT: begin
        ra_addr = set_data ? PC + 1 : set_pc ? ui_in : PC;
        rb_addr = PC + 4;
        wr_addr = PC;
        wr_byte = ui_in;
        wr_en   = set_data && ~run;
      end
      STATE_READ_INST: begin
        ra_addr = A;
        rb_addr = B;
        wr_en   = 1'b0;
        wr_addr = 8'd0;
        wr_byte = 8'd0;
      end
      STATE_READ_DATA: begin
        ra_addr = next_PC;
        rb_addr = next_PC + 4;
        wr_en   = 1'b1;  // Write back the result as we're reading the next instruction
        wr_addr = prev_A;
        wr_byte = result;
      end
      default: begin
        ra_addr = 8'd0;
        rb_addr = 8'd0;
        wr_en   = 1'b0;
      end
    endcase
  end

  always @(posedge clk) begin
    if (~rst_n) begin
      state <= STATE_HALT;
      PC <= 8'h00;
      reg_C <= 8'h00;
      prev_run <= 1'b0;
      prev_A <= 8'h00;
      prev_B_low <= 2'b00;
    end else begin
      prev_run <= run;

      prev_A <= A;
      prev_B_low <= B[1:0];
      reg_C <= C;

      case (state)
        STATE_HALT: begin
          if (set_data) begin
            PC <= PC + 1;
          end
          if (set_pc) begin
            PC <= ui_in;
          end
          if (run && !prev_run && PC <= 8'd252) begin
            state <= STATE_READ_INST;
          end
        end
        STATE_READ_INST: begin
          state <= STATE_READ_DATA;
          reg_C <= C;
        end
        STATE_READ_DATA: begin
          if (~run || next_PC > 252) begin
            state <= STATE_HALT;
          end else begin
            PC <= next_PC;
            state <= STATE_READ_INST;
          end
        end
        default: state <= STATE_HALT;
      endcase
    end
  end

  always @(*) begin
    case (debug)
      0: uo_out = prog_uo_out;
      1: uo_out = PC;
      2: uo_out = A;
      3: uo_out = B;
      4: uo_out = C;
      5: uo_out = value_A;
      6: uo_out = result;
      7: uo_out = {5'b0, state};
    endcase
  end

  // // List all unused inputs to prevent warnings
  wire _unused = &{ena, 1'b0};

endmodule
