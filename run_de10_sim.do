# ===============================================================
# PRAMANA DE10-Nano Virtual Board Self-Check V3
# ===============================================================

catch {quit -sim -force}

if {[file exists work]} {
    catch {vdel -lib work -all}
}
catch {vlib work}
catch {vmap work work}

vlog -sv de10_nano_top.sv
vlog -sv pramana_pe.sv
vlog -sv pramana_accel.sv
vlog -sv tb_de10_nano_sim.sv

vsim -voptargs=+acc work.tb_de10_nano_sim

add wave -divider "Virtual DE10-Nano"
add wave sim:/tb_de10_nano_sim/CLOCK_50
add wave -radix binary sim:/tb_de10_nano_sim/SW
add wave -radix binary sim:/tb_de10_nano_sim/KEY
add wave -radix binary sim:/tb_de10_nano_sim/LED

add wave -divider "Accelerator Self-Check"
add wave sim:/tb_de10_nano_sim/dut/u_pramana/done
add wave sim:/tb_de10_nano_sim/dut/u_pramana/busy
add wave -radix unsigned sim:/tb_de10_nano_sim/dut/u_pramana/active_mac_count
add wave -radix hexadecimal sim:/tb_de10_nano_sim/dut/u_pramana/psum_flat

run 40us
wave zoom full

puts "==============================================================="
puts "PRAMANA VIRTUAL BOARD SELF-CHECK V3 FINISHED"
puts "==============================================================="
