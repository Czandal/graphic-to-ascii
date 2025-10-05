const std = @import("std");
const io = std.io;

var stdout_buffer: [512]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

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
    // 16 characters, from darkest to lightest
    const ascii: [16]u8 = [_]u8{ '@', 'B', '#', '0', '+', '_', '-', ':', '~', '=', '^', '*', '!', '.', '`', ' ' };

    // Compute brightness: r + g + b normalized to [0, 15]
    const sum = (red + green + blue);
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
                // NOTE: bytes are written upside down
                const y = height - i - 1;
                pixels[y * width + j] = (@as(u32, r) << 24) + (@as(u32, g) << 16) + (@as(u32, b) << 8);
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

pub fn print_ascii(bmp: *const BitMap, cell_size: u32) !void {
    var i: u32 = 0;
    while (i < bmp.*.height) : (i += cell_size) {
        var j: u32 = 0;
        while (j < bmp.*.width) : (j += cell_size) {
            // read next NxN cell and avg their red green blue values
            var sum_red: u32 = 0;
            var sum_green: u32 = 0;
            var sum_blue: u32 = 0;

            var cells: u32 = 0;
            var k: u32 = i;
            while (k < @min(bmp.*.height, i + cell_size)) : (k += 1) {
                var l: u32 = j;
                while (l < @min(bmp.*.width, j + cell_size)) : (l += 1) {
                    const rgb = bmp.*.pixels[k * bmp.*.width + l];
                    cells += 1;
                    sum_red += read_red(rgb);
                    sum_green += read_green(rgb);
                    sum_blue += read_blue(rgb);
                }
            }
            const sign = rgb_to_sign(sum_red / cells, sum_green / cells, sum_blue / cells);
            try stdout.writeByte(sign);
        }
        try stdout.writeByte('\n');
    }
    try stdout.flush();
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

    const cell_size_str = args.next() orelse "4";
    const cell_size: u32 = try std.fmt.parseInt(u32, cell_size_str, 10);

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

    try print_ascii(&bmp, cell_size);
}
