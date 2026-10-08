`timescale 1ns/1ps
`default_nettype none

module pramana_pe #(
    parameter integer PSUM_W = 32
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     weight_we,
    input  wire signed [7:0]        weight_data,

    input  wire                     clear_acc,
    input  wire                     compute_en,
    input  wire                     zero_skip_en,
    input  wire                     lane_en,

    input  wire signed [7:0]        activation,

    output reg signed [7:0]         weight_q,
    output reg signed [PSUM_W-1:0]  psum_q,

    output wire                     mac_active
);

    // Signed INT8 x INT8 produces a signed 16-bit product.
    wire signed [15:0] product;

    assign product = $signed(activation) * $signed(weight_q);

    // A PE is active only when computation and its lane are enabled.
    // Zero-weight operations can be skipped.
    assign mac_active =
        compute_en &&
        lane_en &&
        (!zero_skip_en || (weight_q != 8'sd0));

    always @(posedge clk) begin
        if (!rst_n) begin
            weight_q <= 8'sd0;
            psum_q   <= {PSUM_W{1'b0}};
        end else begin

            if (weight_we)
                weight_q <= weight_data;

            if (clear_acc) begin
                psum_q <= {PSUM_W{1'b0}};
            end else if (mac_active) begin
                psum_q <= psum_q +
                    {{(PSUM_W-16){product[15]}}, product};
            end

        end
    end

endmodule

`default_nettype wire