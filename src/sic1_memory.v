/*
 * Copyright (c) 2024-2025 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

/**
 * SIC1 Memory module
 *
 * Takes care of breaking the memory into 8-bit bytes for I/O and instruction fetching, and
 * of handling special memory addresses for I/O.
 * Uses a 64x32 memory internally (built from two 32x32 register files).
 *
 * !IMPORTANT!
 * Write operations most always follow a read operation from the same address (ra_addr), else
 * the data written will be incorrect.
 */

module sic1_memory (
    input wire clk,
    input wire rst_n,

    input wire wr_en,  // Write enable signal
    input wire [7:0] wr_addr,  // Address to write to when wr_en is high
    input wire [7:0] wr_byte,  // Byte to write to memory when wr_en is high

    input  wire [ 5:0] ra_addr,
    output wire [31:0] ra_data,

    input  wire [ 5:0] rb_addr,
    output wire [31:0] rb_data,

    // Breaking out instruction fields:
    input  wire [1:0] PC_low,
    output wire [7:0] out_A,
    output wire [7:0] out_B,
    output wire [7:0] out_C,

    // Breaking out single rb byte:
    input  wire [1:0] rb_byte_idx,
    output wire [7:0] rb_byte,

    // I/O interface:
    input wire [7:0] ui_in,
    output reg [7:0] uo_out,
    output reg out_strobe
);
  parameter ADDR_MAX = 8'd252;
  parameter ADDR_IN = 8'd253;
  parameter ADDR_OUT = 8'd254;

  reg [31:0] w_data;
  reg ra_special;
  reg rb_special;

  always @(*) begin
    case (wr_addr[1:0])
      2'b00: w_data = {ra_data[31:8], wr_byte};
      2'b01: w_data = {ra_data[31:16], wr_byte, ra_data[7:0]};
      2'b10: w_data = {ra_data[31:24], wr_byte, ra_data[15:0]};
      2'b11: w_data = {wr_byte, ra_data[23:0]};
    endcase
  end

  mem_64x32 mem (
      .clk(clk),
      .w_ena(wr_en),
      .w_addr(wr_addr[7:2]),
      .w_data(w_data),
      .ra_addr(ra_addr),
      .ra_data(ra_data),
      .rb_addr(rb_addr),
      .rb_data(rb_data)
  );

  wire [31:0] ra_data_actual = ra_special ? {16'b0, ui_in, ra_data[7:0]} : ra_data;
  wire [31:0] rb_data_actual = rb_special ? {16'b0, ui_in, rb_data[7:0]} : rb_data;

  wire [63:0] inst_data = {rb_data_actual, ra_data_actual} >> (8 * PC_low);
  assign {out_C, out_B, out_A} = inst_data[23:0];
  assign rb_byte = (rb_byte_idx == 2'b00) ? rb_data_actual[7:0] :
                   (rb_byte_idx == 2'b01) ? rb_data_actual[15:8] :
                   (rb_byte_idx == 2'b10) ? rb_data_actual[23:16] :
                                            rb_data_actual[31:24];

  always @(posedge clk) begin
    if (~rst_n) begin
      ra_special <= 1'b0;
      rb_special <= 1'b0;
      uo_out <= 8'h00;
      out_strobe <= 1'b0;
    end else begin
      ra_special <= (ra_addr == ADDR_IN[7:2]);
      rb_special <= (rb_addr == ADDR_IN[7:2]);
      if (wr_addr == ADDR_OUT) begin
        uo_out <= wr_byte;
        out_strobe <= 1'b1;
      end else begin
        out_strobe <= 1'b0;
      end
    end
  end

endmodule
