const std = @import("std");
const expect = std.testing.expect;

pub fn read_red(rgb: u32) u32 {
    return (rgb & (@as(u32, 255) << 24)) >> 24;
}

pub fn read_blue(rgb: u32) u32 {
    return (rgb & (@as(u32, 255) << 16)) >> 16;
}

pub fn read_green(rgb: u32) u32 {
    return (rgb & (@as(u32, 255) << 8)) >> 8;
}

pub fn rgb_to_sign(red: u32, green: u32, blue: u32) u8 {
    const ascii: [16]u8 = [_]u8{ '@', 'B', '#', '0', '+', '_', '-', ':', '~', '=', '^', '*', '!', '.', '`', ' ' };
    const sum = (red + green + blue);
    const idx = @min(15, (sum * 16) / (255 * 3));
    return ascii[idx];
}

test "read_red extracts the red component correctly" {
    const rgb = 0xFF_000000;
    try expect(read_red(rgb) == 0xFF);
    try expect(read_red(0) == 0);
    try expect(read_red(0x7F_000000) == 0x7F);
}

test "read_blue extracts the blue component correctly" {
    const rgb = 0x00_FF_0000;
    try expect(read_blue(rgb) == 0xFF);
    try expect(read_blue(0) == 0);
    try expect(read_blue(0x00_7F_0000) == 0x7F);
}

test "read_green extracts the green component correctly" {
    const rgb = 0x00_00_FF_00;
    try expect(read_green(rgb) == 0xFF);
    try expect(read_green(0) == 0);
    try expect(read_green(0x00_00_7F_00) == 0x7F);
}

test "rgb_to_sign treats r, g and b with the same priority" {
    const input1 = 16;
    const input2 = 240;
    const input3 = 24;
    try expect(rgb_to_sign(input1, input2, input3) == rgb_to_sign(input1, input3, input2));
    try expect(rgb_to_sign(input1, input2, input3) == rgb_to_sign(input3, input1, input2));
    try expect(rgb_to_sign(input1, input2, input3) == rgb_to_sign(input3, input2, input1));
    try expect(rgb_to_sign(input1, input2, input3) == rgb_to_sign(input2, input3, input1));
    try expect(rgb_to_sign(input1, input2, input3) == rgb_to_sign(input2, input1, input3));
}
