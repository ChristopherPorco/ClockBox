################################################################################
# File: clockbox_test.py
# Authors: Christopher Porco
#
# Summary: Simulation test file using cocotb for my 18-224 project, ClockBox
#
# NOTE: As my design is a clock whose outputs are meant to be interpreted only 
#       with the human eye, my primary form of verification was loading my
#       design onto the provided FPGA and using the PCB and decoder to which the
#       design will connect once fabricated. So, I first verified my design 
#       using this hardware, and then completed this testbench as a secondary
#       form of testing (despite it not being used in the tapeout flow for this
#       class).
################################################################################

import os
import logging
import random
import subprocess
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import *
from cocotb.utils import get_sim_time
from cocotb.runner import *

WAIT_ONE_SEC = 10000

def CorrectTime(dut, t3, t2, t1, t0):
    assert(dut.cur_time3 == t3)
    assert(dut.cur_time2 == t2)
    assert(dut.cur_time1 == t1)
    assert(dut.cur_time0 == t0)

async def PressButton(dut):
    for i in range(int(WAIT_ONE_SEC/20) + 1000):
        await FallingEdge(dut.clock)

def CheckTime(dut):
    print(f"{int(str(dut.cur_time3), 2)}{int(str(dut.cur_time2), 2)}:{int(str(dut.cur_time1), 2)}{int(str(dut.cur_time0), 2)}")

@cocotb.test()
async def main(dut):
    print("=========================================")
    print("============= STARTING TEST =============")
    print("=========================================")

    # Run the clock
    # 100nS (=0.1uS) is the period of a 10MHz clock
    cocotb.start_soon(Clock(dut.clock, 2, units="ns").start())

    await FallingEdge(dut.clock)

    # Reset and check
    dut.reset.value = True
    dut.power.value = 0
    dut.mode.value = 0
    dut.start.value = 0
    dut.stop.value = 0
    await FallingEdge(dut.clock)
    await FallingEdge(dut.clock)
    dut.reset.value = False
    await FallingEdge(dut.clock)

    # Check that the current time matches the reset time value
    CorrectTime(dut, 1, 0, 3, 4)

    for i in range(WAIT_ONE_SEC*60):
        await FallingEdge(dut.clock)
        CheckTime(dut)

    # Wait a minute and make sure clock increments
    CorrectTime(dut, 1, 0, 3, 5)

    # Set time
    dut.mode.value = 1
    for i in range(WAIT_ONE_SEC*5):
        await FallingEdge(dut.clock)
        print(f"{int(str(dut.modehold0.out_buttoncount.value), 2)}...{str(dut.modehold0.BUTTON_2SEC.value)}")

    assert(dut.mode_held.value == 1)
    await FallingEdge(dut.clock)

    dut.mode.value = 0
    await FallingEdge(dut.clock)

    dut.stop.value = 1
    await PressButton(dut)
    await PressButton(dut)
    await PressButton(dut)

    dut.stop.value = 0
    await PressButton(dut)

    dut.start.value = 1
    await PressButton(dut)
    await PressButton(dut)

    dut.start.value = 0
    dut.stop.value = 1
    await PressButton(dut)
    dut.stop.value = 0

    CheckTime(dut)
    CorrectTime(dut, 0, 1, 3, 6)

    dut.mode.value = 1
    await PressButton(dut)
    dut.mode.value = 0
    await PressButton(dut)

    # Change mode
    dut.mode.value = 1
    await PressButton(dut)
    dut.mode.value = 0
    await PressButton(dut)

    CorrectTime(dut, 0, 0, 0, 0)

    # Start, stop, reset chrono
    dut.start.value = 1
    await PressButton(dut)
    dut.start.value = 0
    await PressButton(dut)

    for i in range(WAIT_ONE_SEC*2):
        await FallingEdge(dut.clock)

    CorrectTime(dut, 0, 0, 0, 2)

    dut.stop.value = 1
    await PressButton(dut)
    dut.stop.value = 0
    await PressButton(dut)

    CorrectTime(dut, 0, 0, 0, 2)

    dut.stop.value = 1
    for i in range(WAIT_ONE_SEC*5):
        await FallingEdge(dut.clock)

    assert(dut.stop_held.value == 1)
    await FallingEdge(dut.clock)

    dut.stop.value = 0
    await FallingEdge(dut.clock)

    CorrectTime(dut, 0, 0, 0, 0)

    dut.mode.value = 1
    await FallingEdge(dut.clock)
    dut.mode.value = 0
    await FallingEdge(dut.clock)

    CorrectTime(dut, 0, 1, 3, 6)

    print("=========================================")
    print("============== ENDING TEST ==============")
    print("=========================================")

# Main test function
def run_tests():
    sim = os.getenv("SIM", "icarus")

    verilog_sources = ["clockbox.sv"]
    runner = get_runner(sim)
    runner.build(
        verilog_sources=verilog_sources,
        hdl_toplevel="dff",
        always=True,
    )

    runner.test(hdl_toplevel="ClockBox",
                test_module=os.path.splitext(os.path.basename(__file__))[0]+",",
                verbose=False)

if __name__ == "__main__":
    run_tests()