transcript on
if {[file exists work]} { catch {vdel -lib work -all} }
vlib work
vmap work work
vlog -sv pramana_pe.sv
vlog -sv pramana_accel.sv
vlog -sv tb_pramana_final.sv
vsim -voptargs=+acc work.tb_pramana_final
add wave -divider "Control"
add wave sim:/tb_pramana_final/clk
add wave sim:/tb_pramana_final/rst_n
add wave sim:/tb_pramana_final/auth_ok
add wave sim:/tb_pramana_final/start
add wave sim:/tb_pramana_final/clear_acc
add wave sim:/tb_pramana_final/zero_skip_en
add wave -radix hexadecimal sim:/tb_pramana_final/lane_mask
add wave -divider "Status"
add wave sim:/tb_pramana_final/busy
add wave sim:/tb_pramana_final/done
add wave -radix unsigned sim:/tb_pramana_final/active_mac_count
add wave -divider "Activation memory"
add wave -radix signed sim:/tb_pramana_final/dut/act_mem
add wave -divider "PE weights"
add wave -radix signed sim:/tb_pramana_final/dut/pe_weight
add wave -divider "PE activity"
add wave -radix binary sim:/tb_pramana_final/dut/pe_active
add wave -divider "PE partial sums"
add wave -radix signed sim:/tb_pramana_final/dut/pe_psum
add wave -divider "Output columns"
add wave -radix hexadecimal sim:/tb_pramana_final/psum_flat
run 20us
wave zoom full
