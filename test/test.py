# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

from typing import List

import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

ADDR_IN = 253
ADDR_OUT = 254
ADDR_HALT = 255

UIO_RUN = 1 << 0
UIO_SET_PC = 1 << 2
UIO_LOAD_DATA = 1 << 3

REG_NONE = 0
REG_PC = 1
REG_A = 2
REG_B = 3
REG_C = 4
REG_MEM_A = 5
REG_RESULT = 6
REG_STATE = 7


class OutputMonitor:
    def __init__(self, dut):
        self.dut = dut
        self.queue = []
        self._monitor = cocotb.start_soon(self._run())

    async def _run(self):
        while True:
            await RisingEdge(self.dut.out_strobe)
            if int(self.dut.rst_n.value) == 1 and int(self.dut.uo_out.value) != 0:
                self.queue.append(int(self.dut.uo_out.value))

    def get(self):
        return self.queue

    def get_string(self):
        return "".join([chr(c) for c in self.queue])

    def clear(self):
        self.queue = []


class SIC1Driver:
    def __init__(self, dut):
        self.dut = dut
        dut.uio_in.value = 0

        # Set the clock period to 10 us (100 KHz)
        self.clock = Clock(dut.clk, 10, unit="us")
        cocotb.start_soon(self.clock.start())

        self.output = OutputMonitor(dut)

    async def reset(self):
        self.dut._log.info("Reset")
        self.dut.ena.value = 1
        self.dut.ui_in.value = 0
        self.dut.uio_in.value = 0
        self.dut.rst_n.value = 0
        await ClockCycles(self.dut.clk, 10)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 10)

    async def set_pc(self, addr: int):
        self.dut.uio_in.value = UIO_SET_PC
        self.dut.ui_in.value = addr
        await ClockCycles(self.dut.clk, 1)
        self.dut.uio_in.value = 0

    async def write_mem(self, addr: int, data: int):
        await self.set_pc(addr)
        self.dut.uio_in.value = UIO_LOAD_DATA
        self.dut.ui_in.value = data
        await ClockCycles(self.dut.clk, 1)
        self.dut.uio_in.value = 0

    async def write_mem_bytes(self, addr: int, data: List[int]):
        await self.set_pc(addr)
        for d in data:
            self.dut.uio_in.value = UIO_LOAD_DATA
            self.dut.ui_in.value = d
            await ClockCycles(self.dut.clk, 1)
            self.dut.uio_in.value = 0

    async def step(self, n: int = 1):
        for _ in range(n):
            self.dut.uio_in.value = UIO_RUN
            await ClockCycles(self.dut.clk, 1)
            self.dut.uio_in.value = 0
            await ClockCycles(self.dut.clk, 6)  # Each instruction takes 6 clock cycles
        # An extra clock cycle for outputs to stablize:
        await ClockCycles(self.dut.clk, 1)

    async def run(self, limit=10000):
        self.dut.uio_in.value = UIO_RUN
        await ClockCycles(self.dut.clk, 1)
        for _ in range(limit):
            await ClockCycles(self.dut.clk, 1)
            if self.dut.halted.value:
                break
        self.dut.uio_in.value = 0
        # An extra clock cycle for outputs to stablize:
        await ClockCycles(self.dut.clk, 1)

    async def debug_read_reg(self, register: int, signed=False):
        old_uio = self.dut.uio_in.value
        self.dut.uio_in.value = register << 5
        await Timer(50, "ns")  # Wait for the value to be propagated
        result = (
            self.dut.uo_out.value.to_signed()
            if signed
            else self.dut.uo_out.value.to_unsigned()
        )
        self.dut.uio_in.value = old_uio
        return result


@cocotb.test()
async def test_basic_io(dut):
    sic1 = SIC1Driver(dut)
    await sic1.reset()

    await sic1.write_mem(0x00, ADDR_OUT)
    await sic1.write_mem(0x01, ADDR_IN)
    await sic1.write_mem(0x02, 0x10)
    await sic1.set_pc(0x00)

    dut.ui_in.value = 15
    await sic1.step()
    assert dut.uo_out.value.to_signed() == -15


@cocotb.test()
async def test_branching(dut):
    sic1 = SIC1Driver(dut)
    await sic1.reset()

    # fmt: off
    await sic1.write_mem_bytes(0x0, [
        0x00, 0x00, 0x06,  # PC <- 6
        0xfe, 0x00, 0x00,  # OUT <- 0xff, PC <- 0
        0xfe, 0x09, 0x00,  # OUT <- 0x1
        0xff, 0xff, 0xff  # data for previous instruction + HALT
    ])
    # fmt: on

    await sic1.set_pc(0x00)
    await sic1.run()

    assert dut.uo_out.value.to_signed() == 0x01


@cocotb.test()
async def test_print_tinytapeout(dut):
    sic1 = SIC1Driver(dut)
    await sic1.reset()

    # fmt: off
    # Source: programs/print_hello_tinytapeout.sic1
    await sic1.write_mem_bytes(0x0, [
        0x21, 0x22, 0x03, 0x16, 0x16, 0x06, 0x16, 0x21, 0x09, 0x12, 0x12, 0x0c, 0x12, 0x21, 0x0f, 0x21, 
        0x21, 0x12, 0x21, 0x23, 0xff, 0x21, 0x00, 0x18, 0xfe, 0x21, 0x1b, 0x22, 0x24, 0x1e, 0x21, 0x21,
        0x00, 0x00, 0x25, 0x00, 0xff, 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x2c, 0x20, 0x54, 0x69, 0x6e, 0x79,
        0x20, 0x54, 0x61, 0x70, 0x65, 0x6f, 0x75, 0x74, 0x21, 0x00
    ])
    # fmt: on

    await sic1.set_pc(0x00)
    await sic1.run()

    dut._log.info(f"Program output: {sic1.output.get_string()}")
    assert sic1.output.get_string() == "Hello, Tiny Tapeout!"


@cocotb.test()
async def test_count_7segment(dut):
    sic1 = SIC1Driver(dut)
    await sic1.reset()

    # fmt: off
    # Source: programs/count_7segment.sic1
    await sic1.write_mem_bytes(0x0, [
        0x2d, 0x42, 0x03, 0x2e, 0x2e, 0x06, 0x2e, 0x2d, 0x09, 0x2d, 0x2d, 0x0c, 0x2d, 0x2e, 0x0f, 0x22,
        0x22, 0x12, 0x22, 0x2d, 0x15, 0x1e, 0x1e, 0x18, 0x1e, 0x2d, 0x1b, 0x2d, 0x2d, 0x1e, 0x2d, 0x2f,
        0x00, 0x2d, 0x00, 0x24, 0xfe, 0x2d, 0x27, 0x2e, 0x30, 0x2a, 0x2d, 0x2d, 0x0c, 0x00, 0x00, 0x00,
        0xff, 0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f, 0x77, 0x7c, 0x39, 0x5e, 0x79,
        0x71, 0x00, 0x31, 0x00,
    ])
    # fmt: on

    await sic1.set_pc(0x00)
    await sic1.run(limit=500)

    output_values = sic1.output.get()

    # The expected output is a repeating sequence of 0-F in 7-seg encoding
    expected_values = [
        0x3F,  # 0
        0x06,  # 1
        0x5B,  # 2
        0x4F,  # 3
        0x66,  # 4
        0x6D,  # 5
        0x7D,  # 6
        0x07,  # 7
        0x7F,  # 8
        0x6F,  # 9
        0x77,  # A
        0x7C,  # B
        0x39,  # C
        0x5E,  # D
        0x79,  # E
        0x71,  # F
        0x3F,  # repeats...
        0x06,
        0x5B,
    ]
    assert output_values[: len(expected_values)] == expected_values


@cocotb.test()
async def test_debug_interface(dut):
    sic1 = SIC1Driver(dut)
    await sic1.reset()

    assert await sic1.debug_read_reg(REG_PC) == 0

    await sic1.write_mem(0x10, 0x25)
    await sic1.write_mem(0x11, 0x26)
    await sic1.write_mem(0x12, 0x13)
    await sic1.write_mem(0x13, 0x25)
    await sic1.write_mem(0x25, 0x42)
    await sic1.write_mem(0x26, 0x47)
    await sic1.set_pc(0x10)

    assert await sic1.debug_read_reg(REG_PC) == 0x10
    assert await sic1.debug_read_reg(REG_STATE) == 0  # Halt
    dut.uio_in.value = UIO_RUN
    await ClockCycles(dut.clk, 1)
    assert await sic1.debug_read_reg(REG_STATE) == 1  # Read Inst
    assert await sic1.debug_read_reg(REG_A) == 0x25
    assert await sic1.debug_read_reg(REG_B) == 0x26
    assert await sic1.debug_read_reg(REG_C) == 0x13
    await ClockCycles(dut.clk, 1)
    assert await sic1.debug_read_reg(REG_STATE) == 2  # Read Data
    assert await sic1.debug_read_reg(REG_MEM_A) == 0x42
    assert await sic1.debug_read_reg(REG_RESULT, True) == 0x42 - 0x47
    await ClockCycles(dut.clk, 1)
    assert await sic1.debug_read_reg(REG_STATE) == 0  # Halt
    dut.uio_in.value = UIO_RUN
    await ClockCycles(dut.clk, 2)
    assert await sic1.debug_read_reg(REG_STATE) == 2  # Read Data
    assert await sic1.debug_read_reg(REG_MEM_A, True) == 0x42 - 0x47


@cocotb.test()
async def test_internal_memory(dut):
    sic1 = SIC1Driver(dut)
    await sic1.reset()

    rand = random.Random(123)
    data = rand.sample(range(256), k=253)

    # Load data into internal memory
    for addr, value in enumerate(data):
        await sic1.write_mem(addr, value)

    # Read back in random order and verify
    for addr in rand.sample(range(253), k=253):
        await sic1.set_pc(addr)
        value = await sic1.debug_read_reg(REG_MEM_A)
        expected = data[addr]
        assert (
            value == expected
        ), f"Memory mismatch at address {addr}: expected {expected}, got {value}"
