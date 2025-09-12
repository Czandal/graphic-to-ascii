const std = @import("std");
const io = std.io;

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

pub fn rgb_to_sign(rgb: u32) u8 {
    const r: u32 = (rgb & (@as(u32, 255) << 24)) >> 24;
    const g: u32 = (rgb & (@as(u32, 255) << 16)) >> 16;
    const b: u32 = (rgb & (@as(u32, 255) << 8)) >> 8;

    // 16 characters, from darkest to lightest
    const ascii: [16]u8 = [_]u8{ '@', 'B', '#', '0', '+', '_', '-', ':', '~', '=', '^', '*', '!', '.', '`', ' ' };

    // Compute brightness: r + g + b normalized to [0, 15]
    const sum = (r + g + b);
    const idx = @min(15, (sum * 16) / (255 * 3)); // Multiplied by 16 for full range, clamp to 15 just in case

    return ascii[idx];
}

pub const BitMap = struct {
    // all pixels represented in RGB (last 8 bits are left as zeros)
    pixels: []u32,
    alloc: std.mem.Allocator,
    original_bit_depth: u16,
    width: u32,
    height: u32,
    pub fn init(buffer: []u8, alloc: std.mem.Allocator) !BitMap {
        // make sure that we do not read more than the buffer has
        if (buffer.len < 30) {
            return error.BufferTooShort;
        }
        // check if bitmap header is there
        if (!std.mem.eql(u8, buffer[0..2], "BM")) {
            return error.InvalidBitmapHeader;
        }
        const file_size = std.mem.bytesToValue(u32, buffer[2..6]);
        // does file size match the buffer length?
        if (file_size != buffer.len) {
            return error.FileSizeBufferLengthMismatch;
        }
        const pixels_offset = std.mem.bytesToValue(u32, buffer[10..14]);
        const width = std.mem.bytesToValue(u32, buffer[18..22]);
        const height = std.mem.bytesToValue(u32, buffer[22..26]);
        const bit_depth = std.mem.bytesToValue(u16, buffer[28..30]);
        // TODO: Support different bit depths
        if (bit_depth != 24) {
            return error.UnsupportedBitDepth;
        }

        const bytes_per_row_unpadded = width * bit_depth / 8;
        const padding = (4 - (bytes_per_row_unpadded % 4)) % 4;
        const bytes_per_row = padding + bytes_per_row_unpadded;
        // does offset fit?
        if (pixels_offset >= buffer.len) {
            return error.InvalidPixelsOffset;
        }
        if (bytes_per_row * height + pixels_offset > buffer.len) {
            return error.DeclaredMorePixelsThanPossible;
        }
        const pixels = try alloc.alloc(u32, width * height);
        var row_start = pixels_offset;
        var i: u32 = 0;
        while (i < height) : (i += 1) {
            row_start = pixels_offset + bytes_per_row * i;
            var j: u32 = 0;
            while (j < width) : (j += 1) {
                const b = buffer[row_start + 3 * j];
                const g = buffer[row_start + 3 * j + 1];
                const r = buffer[row_start + 3 * j + 2];

                pixels[i * width + j] = (@as(u32, r) << 24) + (@as(u32, g) << 16) + (@as(u32, b) << 8);
            }
        }

        return BitMap{
            .pixels = pixels,
            .original_bit_depth = bit_depth,
            .alloc = alloc,
            .width = width,
            .height = height,
        };
    }
    pub fn deinit(self: BitMap) void {
        self.alloc.free(self.pixels);
    }
};

pub fn print_ascii(bmp: *const BitMap) !void {
    var i: u32 = 0;
    while (i < bmp.*.height) : (i += 1) {
        var j: u32 = 0;
        while (j < bmp.*.width) : (j += 1) {
            const y = bmp.*.height - i;
            const sign = rgb_to_sign(bmp.*.pixels[(y - 1) * bmp.*.width + j]);
            try stdout.writeByte(sign);
        }
        try stdout.writeByte('\n');
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    // Replace argv approach with:
    var args = std.process.args();
    _ = args.skip(); // skip program name
    const file_path = args.next() orelse {
        std.debug.print("Please provide filepath to BMP file\n", .{});
        return;
    };

    // Open the file for reading
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    // Get file size
    const file_size = try file.getEndPos();

    // Allocate buffer and read file
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);
    _ = try file.readAll(buffer);

    const bmp = try BitMap.init(buffer, allocator);
    defer bmp.deinit();

    try print_ascii(&bmp);
}
