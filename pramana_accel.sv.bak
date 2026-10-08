`timescale 1ns/1ps
`default_nettype none

// PRAMANA Secure Adaptive Sparse INT8 Edge-AI Accelerator
// Candidate final compute core, based on TT07 Iterative MAC.
//
// Architectural transformation:
//   single iterative MAC -> 8x8 parallel PE fabric
//   + adaptive lane activation
//   + zero-weight skipping
//   + authenticated weight loading / compute gate
//
// `auth_ok` is deliberately the interface from a separate Root-of-Trust block.
// This file does not pretend to implement SHA-256 itself.

module pramana_accel #(
    parameter integer ROWS = 8,
    parameter integer COLS = 8,
    parameter integer PSUM_W = 32,
    parameter integer PE_COUNT = ROWS * COLS
) (
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               auth_ok,

    input  wire                               weight_we,
    input  wire [$clog2(PE_COUNT)-1:0]        weight_addr,
    input  wire signed [7:0]                  weight_data,

    input  wire                               act_we,
    input  wire [$clog2(ROWS)-1:0]            act_addr,
    input  wire signed [7:0]                  act_data,

    input  wire                               start,
    input  wire                               clear_acc,
    input  wire                               zero_skip_en,
    input  wire [COLS-1:0]                    lane_mask,

    output reg                                done,
    output reg                                busy,
    output reg [6:0]                          active_mac_count,
    output reg [COLS*PSUM_W-1:0]              psum_flat
);

    localparam integer S_IDLE = 0;
    localparam integer S_REDUCE = 1;

    reg state;
    reg signed [7:0] act_mem [0:ROWS-1];

    wire signed [7:0]        pe_weight [0:PE_COUNT-1];
    wire signed [PSUM_W-1:0] pe_psum   [0:PE_COUNT-1];
    wire                     pe_active [0:PE_COUNT-1];

    wire compute_accept;
    wire load_accept;

    reg [6:0] active_count_comb;
    reg signed [PSUM_W-1:0] column_sum_comb;

    integer r, c, idx;

    assign load_accept = auth_ok && weight_we;

    // One compute request is accepted in IDLE. Weight writes and accumulator
    // clears have priority over compute on the same edge by excluding them.
    assign compute_accept = (state == S_IDLE) && start && auth_ok &&
                            !weight_we && !clear_acc;

    // Activation scratchpad.
    always @(posedge clk) begin
        if (!rst_n) begin
            for (r = 0; r < ROWS; r = r + 1)
                act_mem[r] <= 8'sd0;
        end else if (act_we) begin
            act_mem[act_addr] <= act_data;
        end
    end

    // Controller and status.
    always @(posedge clk) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            busy             <= 1'b0;
            done             <= 1'b0;
            active_mac_count <= 7'd0;
            psum_flat        <= {COLS*PSUM_W{1'b0}};
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;

                    // Never leave stale activity visible after authentication
                    // is revoked.
                    if (!auth_ok)
                        active_mac_count <= 7'd0;

                    if (compute_accept) begin
                        active_mac_count <= active_count_comb;
                        state <= S_REDUCE;
                        busy  <= 1'b1;
                    end
                end

                S_REDUCE: begin
                    // All PE accumulators were updated on the previous clock.
                    // Register one reduced 32-bit result per output column.
                    for (c = 0; c < COLS; c = c + 1) begin
                        column_sum_comb = {PSUM_W{1'b0}};
                        for (r = 0; r < ROWS; r = r + 1)
                            column_sum_comb = column_sum_comb + pe_psum[r*COLS+c];
                        psum_flat[c*PSUM_W +: PSUM_W] <= column_sum_comb;
                    end

                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                    busy  <= 1'b0;
                    done  <= 1'b0;
                end
            endcase
        end
    end

    // Activity for the compute edge that will be accepted.
    always @(*) begin
        active_count_comb = 7'd0;
        for (idx = 0; idx < PE_COUNT; idx = idx + 1)
            if (pe_active[idx])
                active_count_comb = active_count_comb + 7'd1;
    end

    // 8x8 explicit PE fabric.
    genvar gr, gc;
    generate
        for (gr = 0; gr < ROWS; gr = gr + 1) begin : GEN_ROW
            for (gc = 0; gc < COLS; gc = gc + 1) begin : GEN_COL
                localparam integer PE_IDX = gr*COLS + gc;
                wire pe_weight_we;

                assign pe_weight_we = load_accept && (weight_addr == PE_IDX);

                pramana_pe #(.PSUM_W(PSUM_W)) u_pe (
                    .clk          (clk),
                    .rst_n        (rst_n),
                    .weight_we    (pe_weight_we),
                    .weight_data  (weight_data),
                    .clear_acc    (clear_acc),
                    .compute_en   (compute_accept),
                    .zero_skip_en (zero_skip_en),
                    .lane_en      (lane_mask[gc]),
                    .activation   (act_mem[gr]),
                    .weight_q     (pe_weight[PE_IDX]),
                    .psum_q       (pe_psum[PE_IDX]),
                    .mac_active   (pe_active[PE_IDX])
                );
            end
        end
    endgenerate

endmodule

`default_nettype wire
