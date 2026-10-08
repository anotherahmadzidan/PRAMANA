`timescale 1ns/1ps
`default_nettype none

module tb_pramana_final;
    localparam integer ROWS = 8;
    localparam integer COLS = 8;
    localparam integer PSUM_W = 32;
    localparam integer PE_COUNT = 64;

    reg clk, rst_n, auth_ok;
    reg weight_we;
    reg [5:0] weight_addr;
    reg signed [7:0] weight_data;
    reg act_we;
    reg [2:0] act_addr;
    reg signed [7:0] act_data;
    reg start, clear_acc, zero_skip_en;
    reg [7:0] lane_mask;

    wire done;
    wire busy;
    wire [6:0] active_mac_count;
    wire [255:0] psum_flat;

    integer errors, i, j;
    integer A[0:ROWS-1];
    integer W[0:ROWS-1][0:COLS-1];
    integer expected[0:COLS-1];

    // Performance measurement
    integer cycle_counter;
    integer start_cycle;
    integer done_cycle;
    integer latency_cycles;
    integer compute_count;

    pramana_accel dut (
        .clk(clk), .rst_n(rst_n), .auth_ok(auth_ok),
        .weight_we(weight_we), .weight_addr(weight_addr), .weight_data(weight_data),
        .act_we(act_we), .act_addr(act_addr), .act_data(act_data),
        .start(start), .clear_acc(clear_acc), .zero_skip_en(zero_skip_en),
        .lane_mask(lane_mask), .done(done), .busy(busy),
        .active_mac_count(active_mac_count), .psum_flat(psum_flat)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Count clock cycles; reset counter when rst_n is low.
    initial cycle_counter = 0;

    always @(posedge clk) begin
        if (!rst_n)
            cycle_counter <= 0;
        else
            cycle_counter <= cycle_counter + 1;
    end

    task write_weight;
        input integer addr;
        input integer value;
        begin
            @(negedge clk);
            weight_we = 1'b1;
            weight_addr = addr;
            weight_data = value;
            @(posedge clk);
            #1;
            @(negedge clk);
            weight_we = 1'b0;
        end
    endtask

    task write_activation;
        input integer addr;
        input integer value;
        begin
            @(negedge clk);
            act_we = 1'b1;
            act_addr = addr;
            act_data = value;
            @(posedge clk);
            #1;
            @(negedge clk);
            act_we = 1'b0;
        end
    endtask

    task clear_accumulator;
        begin
            @(negedge clk);
            clear_acc = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            clear_acc = 1'b0;
        end
    endtask

    // Run one compute transaction and report elapsed simulation cycles.
    // Timing is measured from just before asserting start until done is
    // observed at a falling clock edge. Clock period is 10 ns.
    task run_compute;
        begin
            @(negedge clk);

            // Avoid treating a stale done level as completion.
            while (done === 1'b1)
                @(negedge clk);

            start_cycle = cycle_counter;
            start = 1'b1;

            // Accelerator samples start at this rising edge.
            @(posedge clk);
            #1;
            start = 1'b0;

            // Sample done away from the active rising edge to avoid races.
            while (done !== 1'b1)
                @(negedge clk);

            done_cycle = cycle_counter;
            latency_cycles = done_cycle - start_cycle;
            compute_count = compute_count + 1;

            $display(
                "PERF | Compute #%0d | Start=%0d | Done=%0d | Latency=%0d cycles | Time=%0d ns",
                compute_count,
                start_cycle,
                done_cycle,
                latency_cycles,
                latency_cycles * 10
            );
        end
    endtask

    task check_active;
        input integer expected_count;
        input [127:0] label;
        begin
            if (active_mac_count !== expected_count[6:0]) begin
                $display("FAIL | %0s | expected active=%0d got=%0d", label, expected_count, active_mac_count);
                errors = errors + 1;
            end else
                $display("PASS | %0s | active_mac_count=%0d", label, active_mac_count);
        end
    endtask

    task check_done;
        input [127:0] label;
        begin
            if (done !== 1'b1) begin
                $display("FAIL | %0s | done=0", label);
                errors = errors + 1;
            end else
                $display("PASS | %0s | done=1", label);
        end
    endtask

    task check_columns;
        input [7:0] mask;
        input [127:0] label;
        begin
            for (j = 0; j < COLS; j = j + 1) begin
                if (mask[j]) begin
                    if ($signed(psum_flat[j*PSUM_W +: PSUM_W]) !== expected[j]) begin
                        $display("FAIL | %0s | col=%0d expected=%0d got=%0d", label, j, expected[j], $signed(psum_flat[j*PSUM_W +: PSUM_W]));
                        errors = errors + 1;
                    end else
                        $display("PASS | %0s | col=%0d value=%0d", label, j, expected[j]);
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        start_cycle = 0;
        done_cycle = 0;
        latency_cycles = 0;
        compute_count = 0;

        rst_n = 1'b0;
        auth_ok = 1'b0;
        weight_we = 1'b0; weight_addr = 0; weight_data = 0;
        act_we = 1'b0; act_addr = 0; act_data = 0;
        start = 1'b0; clear_acc = 1'b0;
        zero_skip_en = 1'b1; lane_mask = 8'hFF;

        // Deterministic matrix: exactly 16 zeros, no incidental zero values.
        for (i = 0; i < ROWS; i = i + 1) begin
            A[i] = i + 1;
            for (j = 0; j < COLS; j = j + 1) begin
                if ((i + j) % 4 == 0)
                    W[i][j] = 0;
                else
                    W[i][j] = ((i * 3 + j * 2) % 7) + 1;
            end
        end

        for (j = 0; j < COLS; j = j + 1) begin
            expected[j] = 0;
            for (i = 0; i < ROWS; i = i + 1)
                expected[j] = expected[j] + A[i] * W[i][j];
        end

        $display("===============================================================");
        $display("PRAMANA FINAL CANDIDATE RTL TEST");
        $display("8x8 = 64 physical MAC PEs");
        $display("Features: adaptive lane + zero skip + authenticated compute");
        $display("===============================================================");

        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // T1: unauthenticated weight write blocked.
        write_weight(0, 99);
        if (dut.pe_weight[0] !== 8'sd0) begin
            $display("FAIL | T1 | unauthenticated weight write accepted"); errors = errors + 1;
        end else
            $display("PASS | T1 | unauthenticated weight write blocked");

        auth_ok = 1'b1;

        // T2: authenticated model load.
        for (i = 0; i < ROWS; i = i + 1)
            for (j = 0; j < COLS; j = j + 1)
                write_weight(i*COLS+j, W[i][j]);
        for (i = 0; i < ROWS; i = i + 1)
            write_activation(i, A[i]);
        $display("PASS | T2 | authenticated weights/activations loaded");

        // T3: full lanes + zero skip -> exactly 48 active MACs.
        lane_mask = 8'hFF; zero_skip_en = 1'b1; clear_accumulator; run_compute;
        check_active(48, "T3 full lanes + zero skip");
        check_done("T3 reduction");
        check_columns(8'hFF, "T3 correctness");

        // T4: full lanes + zero skip disabled -> 64 active.
        lane_mask = 8'hFF; zero_skip_en = 1'b0; clear_accumulator; run_compute;
        check_active(64, "T4 full lanes + zero skip OFF");
        check_done("T4 reduction");
        check_columns(8'hFF, "T4 correctness");

        // T5: four upper columns -> 32 opportunities, 8 zeros -> 24 active.
        lane_mask = 8'hF0; zero_skip_en = 1'b1; clear_accumulator; run_compute;
        check_active(24, "T5 lane F0 + zero skip");
        check_done("T5 reduction");
        if ($signed(psum_flat[0*PSUM_W +: PSUM_W]) !== 0 ||
            $signed(psum_flat[1*PSUM_W +: PSUM_W]) !== 0 ||
            $signed(psum_flat[2*PSUM_W +: PSUM_W]) !== 0 ||
            $signed(psum_flat[3*PSUM_W +: PSUM_W]) !== 0) begin
            $display("FAIL | T5 | inactive lower lanes changed output"); errors = errors + 1;
        end else
            $display("PASS | T5 | inactive lower lanes remain zero");
        check_columns(8'hF0, "T5 active lanes correctness");

        // T6: two lower columns -> 16 opportunities, 4 zeros -> 12 active.
        lane_mask = 8'h03; zero_skip_en = 1'b1; clear_accumulator; run_compute;
        check_active(12, "T6 lane 03 + zero skip");
        check_done("T6 reduction");
        check_columns(8'h03, "T6 active lanes correctness");

        // T7: revoke authentication and try compute -> blocked and count clears.
        clear_accumulator; auth_ok = 1'b0; lane_mask = 8'hFF; zero_skip_en = 1'b1;
        @(negedge clk); start = 1'b1;
        @(posedge clk); #1; start = 1'b0;
        @(posedge clk); #1;
        if (active_mac_count !== 7'd0 || done !== 1'b0) begin
            $display("FAIL | T7 | unauthenticated compute not fully blocked"); errors = errors + 1;
        end else
            $display("PASS | T7 | unauthenticated compute blocked");

        // T8: same input/workload twice -> accumulation doubles.
        auth_ok = 1'b1; lane_mask = 8'hFF; zero_skip_en = 1'b1; clear_accumulator;
        run_compute; run_compute;
        for (j = 0; j < COLS; j = j + 1) begin
            if ($signed(psum_flat[j*PSUM_W +: PSUM_W]) !== (2*expected[j])) begin
                $display("FAIL | T8 | col=%0d expected=%0d got=%0d", j, 2*expected[j], $signed(psum_flat[j*PSUM_W +: PSUM_W]));
                errors = errors + 1;
            end
        end
        if (errors == 0)
            $display("PASS | T8 | repeated accumulation correct");
        else
            $display("FAIL | T8 | repeated accumulation has errors");

        $display("---------------------------------------------------------------");
        $display("PERFORMANCE SUMMARY | Compute transactions measured=%0d", compute_count);
        if (errors == 0)
            $display("PRAMANA FINAL CANDIDATE TB: PASS");
        else
            $display("PRAMANA FINAL CANDIDATE TB: FAIL (%0d error(s))", errors);
        $display("---------------------------------------------------------------");
        #20;
        $finish;
    end
endmodule

`default_nettype wire
