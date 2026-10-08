`timescale 1ns/1ps
`default_nettype none

module tb_de10_nano_sim;

    reg        CLOCK_50;
    reg [3:0]  SW;
    reg [1:0]  KEY;
    wire [3:0] LED;

    integer errors;
    integer start_time_ns;
    integer done_time_ns;
    integer latency_ns;

    // Expected 8x8 reduction from the deterministic PRAMANA workload.
    integer expected [0:7];

    de10_nano_top dut (
        .CLOCK_50(CLOCK_50),
        .SW(SW),
        .KEY(KEY),
        .LED(LED)
    );

    // Virtual DE10-Nano clock: 50 MHz, 20 ns period.
    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    task press_reset;
        begin
            KEY[1] = 1'b0;
            repeat (3) @(posedge CLOCK_50);
            KEY[1] = 1'b1;
            repeat (3) @(posedge CLOCK_50);
        end
    endtask

    task press_start;
        begin
            KEY[0] = 1'b0;
            @(posedge CLOCK_50);
            KEY[0] = 1'b1;
        end
    endtask

    task wait_done_and_check;
        input [7:0] mask;
        input [127:0] label;
        integer timeout_cycles;
        integer j;
        begin
            timeout_cycles = 0;

            // Wait for the accelerator instance inside the board wrapper.
            while ((dut.u_pramana.done !== 1'b1) &&
                   (timeout_cycles < 500)) begin
                @(posedge CLOCK_50);
                timeout_cycles = timeout_cycles + 1;
            end

            if (dut.u_pramana.done !== 1'b1) begin
                $display(
                    "FAIL | %0s | timeout waiting for u_pramana.done",
                    label
                );
                errors = errors + 1;
            end
            else begin
                done_time_ns = $time;
                latency_ns = done_time_ns - start_time_ns;

                $display(
                    "BOARD | %0s | DONE at %0t ns | elapsed from START=%0d ns",
                    label, $time, latency_ns
                );

                for (j = 0; j < 8; j = j + 1) begin
                    if (mask[j]) begin
                        if ($signed(
                            dut.u_pramana.psum_flat[j*32 +: 32]
                        ) !== expected[j]) begin
                            $display(
                                "FAIL | %0s | col=%0d expected=%0d got=%0d",
                                label,
                                j,
                                expected[j],
                                $signed(dut.u_pramana.psum_flat[j*32 +: 32])
                            );
                            errors = errors + 1;
                        end
                        else begin
                            $display(
                                "PASS | %0s | col=%0d value=%0d",
                                label, j, expected[j]
                            );
                        end
                    end
                    else begin
                        if ($signed(
                            dut.u_pramana.psum_flat[j*32 +: 32]
                        ) !== 0) begin
                            $display(
                                "FAIL | %0s | inactive col=%0d is not zero",
                                label, j
                            );
                            errors = errors + 1;
                        end
                    end
                end
            end
        end
    endtask

    task check_no_done;
        input [127:0] label;
        integer k;
        begin
            k = 0;
            while (k < 100) begin
                @(posedge CLOCK_50);
                if (dut.u_pramana.done === 1'b1) begin
                    $display(
                        "FAIL | %0s | unexpected done while authentication is OFF",
                        label
                    );
                    errors = errors + 1;
                    k = 100;
                end
                else begin
                    k = k + 1;
                end
            end

            if (dut.u_pramana.done !== 1'b1)
                $display("PASS | %0s | compute blocked", label);
        end
    endtask

    initial begin
        expected[0] = 96;
        expected[1] = 99;
        expected[2] = 126;
        expected[3] = 142;
        expected[4] = 105;
        expected[5] = 74;
        expected[6] = 124;
        expected[7] = 107;

        errors = 0;
        SW  = 4'b0001;
        KEY = 2'b11;

        $display("===============================================================");
        $display("PRAMANA DE10-NANO VIRTUAL BOARD SELF-CHECK V3");
        $display("50 MHz virtual clock / 20 ns period");
        $display("Checks internal accelerator DONE + PSUM through board wrapper");
        $display("===============================================================");

        press_reset;
        repeat (20) @(posedge CLOCK_50);

        // Case 1: AUTH ON + ZERO SKIP + ALL LANES.
        SW = 4'b0011;
        $display("CASE1 | SW=%b | auth + skip + all lanes", SW);
        @(negedge CLOCK_50);
        start_time_ns = $time;
        press_start;
        wait_done_and_check(8'hFF, "CASE1");

        // Give done/state machine time to return to idle.
        repeat (10) @(posedge CLOCK_50);

        // Case 2: AUTH ON + ZERO SKIP OFF + ALL LANES.
        SW = 4'b0001;
        $display("CASE2 | SW=%b | auth + no-skip + all lanes", SW);
        @(negedge CLOCK_50);
        start_time_ns = $time;
        press_start;
        wait_done_and_check(8'hFF, "CASE2");

        repeat (10) @(posedge CLOCK_50);

        // Case 3: AUTH ON + ZERO SKIP + F0.
        SW = 4'b0111;
        $display("CASE3 | SW=%b | auth + skip + F0", SW);
        @(negedge CLOCK_50);
        start_time_ns = $time;
        press_start;
        wait_done_and_check(8'hF0, "CASE3");

        repeat (10) @(posedge CLOCK_50);

        // Case 4: AUTH ON + ZERO SKIP + 03.
        SW = 4'b1011;
        $display("CASE4 | SW=%b | auth + skip + 03", SW);
        @(negedge CLOCK_50);
        start_time_ns = $time;
        press_start;
        wait_done_and_check(8'h03, "CASE4");

        repeat (10) @(posedge CLOCK_50);

        // Case 5: AUTH OFF. DONE must not appear.
        SW = 4'b0010;
        $display("CASE5 | SW=%b | auth OFF", SW);
        @(negedge CLOCK_50);
        press_start;
        check_no_done("CASE5");

        $display("---------------------------------------------------------------");
        if (errors == 0) begin
            $display("PRAMANA DE10-NANO VIRTUAL BOARD SELF-CHECK: PASS");
        end
        else begin
            $display(
                "PRAMANA DE10-NANO VIRTUAL BOARD SELF-CHECK: FAIL (%0d errors)",
                errors
            );
        end
        $display("---------------------------------------------------------------");

        #100;
        $finish;
    end

endmodule

`default_nettype wire
