`timescale 1ns/1ps
`default_nettype none

module de10_nano_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  SW,
    input  wire [1:0]  KEY,
    output wire [3:0]  LED
);

    wire rst_n   = KEY[1];
    wire auth_ok = SW[0];

    reg  key0_d;
    wire start_pulse = (~KEY[0]) & key0_d;

    localparam [2:0] C_IDLE    = 3'd0;
    localparam [2:0] C_WLOAD   = 3'd1;
    localparam [2:0] C_ALOAD   = 3'd2;
    localparam [2:0] C_CLEAR   = 3'd3;
    localparam [2:0] C_COMPUTE = 3'd4;
    localparam [2:0] C_WAIT    = 3'd5;

    reg [2:0] ctrl_state;

    reg [5:0] waddr;
    reg [2:0] aaddr;

    reg             weight_we;
    reg signed [7:0] weight_data;

    reg             act_we;
    reg signed [7:0] act_data;

    reg start;
    reg clear_acc;

    wire done;
    wire busy;

    wire [6:0]   active_mac_count;
    wire [255:0] psum_flat;

    reg [7:0] lane_mask;

    // ------------------------------------------------------------
    // Deterministic test weights.
    // Address format:
    //   addr[5:3] = row
    //   addr[2:0] = column
    //
    // Exactly 16 zero weights are generated.
    // ------------------------------------------------------------
    function automatic signed [7:0] weight_value;
        input [5:0] addr;

        reg [2:0] rr;
        reg [2:0] cc;
        reg [3:0] sum_rc;
        reg [5:0] calc;

        begin
            rr = addr[5:3];
            cc = addr[2:0];

            sum_rc = {1'b0, rr} + {1'b0, cc};

            calc = (rr * 6'd3) + (cc * 6'd2);

            if (sum_rc[1:0] == 2'b00)
                weight_value = 8'sd0;
            else
                weight_value = (calc % 6'd7) + 8'd1;
        end
    endfunction

    // Activations A = 1..8.
    function automatic signed [7:0] activation_value;
        input [2:0] addr;

        begin
            activation_value = {5'b0, addr} + 8'd1;
        end
    endfunction

    // ------------------------------------------------------------
    // Lane mask:
    // 00 = all eight columns
    // 01 = upper four columns
    // 10 = lower two columns
    // 11 = all eight columns
    // ------------------------------------------------------------
    always @(*) begin
        case (SW[3:2])
            2'b00:   lane_mask = 8'hFF;
            2'b01:   lane_mask = 8'hF0;
            2'b10:   lane_mask = 8'h03;
            default: lane_mask = 8'hFF;
        endcase
    end

    // Generate a one-cycle start request from KEY[0].
    always @(posedge CLOCK_50) begin
        if (!rst_n)
            key0_d <= 1'b1;
        else
            key0_d <= KEY[0];
    end

    // ------------------------------------------------------------
    // Combinational controller outputs.
    // ------------------------------------------------------------
    always @(*) begin
        weight_we   = 1'b0;
        weight_data = 8'sd0;

        act_we      = 1'b0;
        act_data    = 8'sd0;

        start       = 1'b0;
        clear_acc   = 1'b0;

        case (ctrl_state)
            C_WLOAD: begin
                weight_we   = auth_ok;
                weight_data = weight_value(waddr);
            end

            C_ALOAD: begin
                act_we   = 1'b1;
                act_data = activation_value(aaddr);
            end

            C_CLEAR: begin
                clear_acc = 1'b1;
            end

            C_COMPUTE: begin
                start = 1'b1;
            end

            default: begin
            end
        endcase
    end

    // ------------------------------------------------------------
    // Bring-up controller.
    // ------------------------------------------------------------
    always @(posedge CLOCK_50) begin
        if (!rst_n) begin
            ctrl_state <= C_IDLE;
            waddr      <= 6'd0;
            aaddr      <= 3'd0;
        end else begin
            case (ctrl_state)

                C_IDLE: begin
                    if (start_pulse && auth_ok) begin
                        waddr      <= 6'd0;
                        ctrl_state <= C_WLOAD;
                    end
                end

                C_WLOAD: begin
                    if (!auth_ok) begin
                        // Abort loading if authentication is revoked.
                        ctrl_state <= C_IDLE;
                        waddr      <= 6'd0;
                    end else if (waddr == 6'd63) begin
                        aaddr      <= 3'd0;
                        ctrl_state <= C_ALOAD;
                    end else begin
                        waddr <= waddr + 6'd1;
                    end
                end

                C_ALOAD: begin
                    if (aaddr == 3'd7) begin
                        ctrl_state <= C_CLEAR;
                    end else begin
                        aaddr <= aaddr + 3'd1;
                    end
                end

                C_CLEAR: begin
                    ctrl_state <= C_COMPUTE;
                end

                C_COMPUTE: begin
                    ctrl_state <= C_WAIT;
                end

                C_WAIT: begin
                    if (done)
                        ctrl_state <= C_IDLE;
                end

                default: begin
                    ctrl_state <= C_IDLE;
                end

            endcase
        end
    end

    // ------------------------------------------------------------
    // PRAMANA accelerator instance.
    // ------------------------------------------------------------
    pramana_accel #(
        .ROWS   (8),
        .COLS   (8),
        .PSUM_W (32)
    ) u_pramana (
        .clk              (CLOCK_50),
        .rst_n            (rst_n),
        .auth_ok          (auth_ok),

        .weight_we        (weight_we),
        .weight_addr      (waddr),
        .weight_data      (weight_data),

        .act_we           (act_we),
        .act_addr         (aaddr),
        .act_data         (act_data),

        .start             (start),
        .clear_acc         (clear_acc),

        .zero_skip_en      (SW[1]),
        .lane_mask         (lane_mask),

        .done              (done),
        .busy              (busy),
        .active_mac_count  (active_mac_count),
        .psum_flat         (psum_flat)
    );

    assign LED[0] = busy;
    assign LED[1] = done;
    assign LED[2] = auth_ok;
    assign LED[3] = (active_mac_count != 7'd0);

endmodule

`default_nettype wire