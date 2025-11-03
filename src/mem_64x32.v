/*
 * Copyright (c) 2024-2025 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

/**
  * 64x32 memory module built from two 32x32 register files.
  * The upper bit of the address selects which register file to use.
  * The lower 5 bits of the address select the register within the file.
  *
  */
module mem_64x32 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        w_ena,
    input  wire [ 5:0] w_addr,
    input  wire [31:0] w_data,
    input  wire [ 5:0] ra_addr,
    output wire [31:0] ra_data,
    input  wire [ 5:0] rb_addr,
    output wire [31:0] rb_data
);
  wire [31:0] mem_low_ra_data;
  wire [31:0] mem_low_rb_data;
  wire [31:0] mem_high_ra_data;
  wire [31:0] mem_high_rb_data;

  reg bank_sel_a;
  reg bank_sel_b;

  assign ra_data = bank_sel_a ? mem_high_ra_data : mem_low_ra_data;
  assign rb_data = bank_sel_b ? mem_high_rb_data : mem_low_rb_data;

  rf_top mem_low (
      .w_data(w_data),
      .w_addr(w_addr[4:0]),
      .w_ena(w_addr[5] == 1'b0 && w_ena),
      .ra_addr(ra_addr[4:0]),
      .rb_addr(rb_addr[4:0]),
      .ra_data(mem_low_ra_data),
      .rb_data(mem_low_rb_data),
      .clk(clk)
  );

  rf_top mem_high (
      .w_data(w_data),
      .w_addr(w_addr[4:0]),
      .w_ena(w_addr[5] == 1'b1 && w_ena),
      .ra_addr(ra_addr[4:0]),
      .rb_addr(rb_addr[4:0]),
      .ra_data(mem_high_ra_data),
      .rb_data(mem_high_rb_data),
      .clk(clk)
  );

  always @(posedge clk) begin
    if (~rst_n) begin
      bank_sel_a <= 1'b0;
      bank_sel_b <= 1'b0;
    end else begin
      bank_sel_a <= ra_addr[5];
      bank_sel_b <= rb_addr[5];
    end
  end
endmodule
