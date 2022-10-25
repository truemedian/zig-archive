const std = @import("std");

const mem = std.mem;

// Add more methods as they're supported
pub const CompressionMethod = enum(u16) {
    none = 0,
    deflated = 8,
    enhanced_deflated,
    _,
};

const Crc32Poly = @intToEnum(std.hash.crc.Polynomial, 0xEDB88320);
pub const Crc32 = std.hash.crc.Crc32WithPoly(Crc32Poly);

pub const Version = struct {
    pub const Vendor = enum(u8) {
        dos = 0,
        amiga,
        openvms,
        unix,
        vm,
        atari,
        os2_hpfs,
        macintosh,
        z_system,
        cp_m,
        ntfs,
        mvs,
        vse,
        acorn,
        vfat,
        alt_mvs,
        beos,
        tandem,
        os400,
        osx,
        _,
    };

    vendor: Vendor,
    major: u8,
    minor: u8,

    pub fn read(entry: u16) Version {
        var ver: Version = undefined;

        ver.major = @truncate(u8, entry) / 10;
        ver.minor = @truncate(u8, entry) % 10;
        ver.vendor = @intToEnum(Vendor, @truncate(u8, entry >> 8));

        return ver;
    }

    pub fn write(self: Version) u16 {
        const version = @as(u16, self.major * 10 + self.minor);
        const vendor = @as(u16, @enumToInt(self.vendor)) << 8;

        return version | vendor;
    }

    pub fn check(self: Version) bool {
        if (self.major < 4) {
            return true;
        } else if (self.major == 4 and self.minor <= 5) {
            return true;
        } else {
            return false;
        }
    }
};

pub const GeneralPurposeBitFlag = packed struct {
    encrypted: bool,
    compression1: u1,
    compression2: u1,
    data_descriptor: bool,
    enhanced_deflation: u1,
    compressed_patched: bool,
    strong_encryption: bool,
    __7_reserved: u1,
    __8_reserved: u1,
    __9_reserved: u1,
    __10_reserved: u1,
    is_utf8: bool,
    __12_reserved: u1,
    mask_headers: bool,
    __14_reserved: u1,
    __15_reserved: u1,

    pub fn read(entry: u16) GeneralPurposeBitFlag {
        return @bitCast(GeneralPurposeBitFlag, entry);
    }

    pub fn write(self: GeneralPurposeBitFlag) u16 {
        return @bitCast(u16, self);
    }
};

pub const DosTimestamp = struct {
    second: u6,
    minute: u6,
    hour: u5,
    day: u5,
    month: u4,
    year: u12,

    pub fn read(entry: [2]u16) DosTimestamp {
        var self: DosTimestamp = undefined;

        self.second = @as(u6, @truncate(u5, entry[0])) << 1;
        self.minute = @truncate(u6, entry[0] >> 5);
        self.hour = @truncate(u5, entry[0] >> 11);

        self.day = @truncate(u5, entry[1]);
        self.month = @truncate(u4, entry[1] >> 5);
        self.year = @as(u12, @truncate(u7, entry[1] >> 9)) + 1980;

        return self;
    }

    pub fn write(self: DosTimestamp) [2]u16 {
        var buf: [2]u8 = undefined;

        const second = @as(u16, @truncate(u5, self.second >> 1));
        const minute = @as(u16, @truncate(u5, self.minute) << 5);
        const hour = @as(u16, @truncate(u5, self.hour) << 11);

        buf[0] = second | minute | hour;

        const day = self.day;
        const month = self.month << 5;
        const year = (self.year - 1980) << 11;

        buf[1] = day | month | year;

        return buf;
    }
};

pub const LocalFileRecord = struct {
    pub const signature = 0x04034b50;
    pub const size = 30;

    signature: u32,
    version: u16,
    flags: GeneralPurposeBitFlag,
    compression_method: CompressionMethod,
    last_mod_time: u16,
    last_mod_date: u16,
    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
    filename_len: u16,
    extra_len: u16,

    pub fn read(reader: anytype) !LocalFileRecord {
        var self: LocalFileRecord = undefined;

        var buf: [30]u8 = undefined;
        const nread = try reader.readAll(&buf);
        if (nread == 0) return error.EndOfStream;

        self.signature = mem.readIntLittle(u32, buf[0..4]);
        if (self.signature != signature) return error.InvalidSignature;

        self.version = mem.readIntLittle(u16, buf[4..6]);
        self.flags = @bitCast(GeneralPurposeBitFlag, mem.readIntLittle(u16, buf[6..8]));
        self.compression_method = @intToEnum(CompressionMethod, mem.readIntLittle(u16, buf[8..10]));
        self.last_mod_time = mem.readIntLittle(u16, buf[10..12]);
        self.last_mod_date = mem.readIntLittle(u16, buf[12..14]);
        self.crc32 = mem.readIntLittle(u32, buf[14..18]);
        self.compressed_size = mem.readIntLittle(u32, buf[18..22]);
        self.uncompressed_size = mem.readIntLittle(u32, buf[22..26]);
        self.filename_len = mem.readIntLittle(u16, buf[26..28]);
        self.extra_len = mem.readIntLittle(u16, buf[28..30]);

        return self;
    }

    pub fn write(self: LocalFileRecord, writer: anytype) !void {
        try writer.writeIntLittle(u32, signature);

        try writer.writeIntLittle(u16, self.version);
        try writer.writeIntLittle(u16, @bitCast(u16, self.flags));
        try writer.writeIntLittle(u16, @enumToInt(self.compression_method));
        try writer.writeIntLittle(u16, self.last_mod_time);
        try writer.writeIntLittle(u16, self.last_mod_date);
        try writer.writeIntLittle(u32, self.crc32);
        try writer.writeIntLittle(u32, self.compressed_size);
        try writer.writeIntLittle(u32, self.uncompressed_size);
        try writer.writeIntLittle(u16, self.filename_len);
        try writer.writeIntLittle(u16, self.extra_len);
    }
};

pub const CentralDirectoryRecord = struct {
    pub const signature = 0x02014b50;

    version_made: u16,
    version_needed: u16,
    flags: GeneralPurposeBitFlag,
    compression_method: CompressionMethod,
    last_mod_time: u16,
    last_mod_date: u16,
    crc32: u32,
    compressed_size: u64,
    uncompressed_size: u64,
    filename_len: u16,
    extra_len: u16 = 0,
    comment_len: u16 = 0,
    disk_number_start: u16 = 0,
    internal_attributes: u16 = 0,
    external_attributes: u32 = 0,
    local_offset: u64,

    filename_idx: usize,

    pub fn read(reader: anytype) !CentralDirectoryRecord {
        const sig = try reader.readIntLittle(u32);
        if (sig != signature) return error.InvalidSignature;

        var record: CentralDirectoryRecord = undefined;

        var buf: [42]u8 = undefined;
        const nread = try reader.readAll(&buf);
        if (nread == 0) return error.EndOfStream;

        record.version_made = mem.readIntLittle(u16, buf[0..2]);
        record.version_needed = mem.readIntLittle(u16, buf[2..4]);
        record.flags = @bitCast(GeneralPurposeBitFlag, mem.readIntLittle(u16, buf[4..6]));
        record.compression_method = @intToEnum(CompressionMethod, mem.readIntLittle(u16, buf[6..8]));
        record.last_mod_time = mem.readIntLittle(u16, buf[8..10]);
        record.last_mod_date = mem.readIntLittle(u16, buf[10..12]);
        record.crc32 = mem.readIntLittle(u32, buf[12..16]);
        record.compressed_size = mem.readIntLittle(u32, buf[16..20]);
        record.uncompressed_size = mem.readIntLittle(u32, buf[20..24]);
        record.filename_len = mem.readIntLittle(u16, buf[24..26]);
        record.extra_len = mem.readIntLittle(u16, buf[26..28]);
        record.comment_len = mem.readIntLittle(u16, buf[28..30]);
        record.disk_number_start = mem.readIntLittle(u16, buf[30..32]);
        record.internal_attributes = mem.readIntLittle(u16, buf[32..34]);
        record.external_attributes = mem.readIntLittle(u32, buf[34..38]);
        record.local_offset = mem.readIntLittle(u32, buf[38..42]);

        return record;
    }

    pub fn write(self: CentralDirectoryRecord, writer: anytype) !void {
        try writer.writeIntLittle(u32, signature);

        try writer.writeIntLittle(u16, self.version_made);
        try writer.writeIntLittle(u16, self.version_needed);
        try writer.writeIntLittle(u16, @bitCast(u16, self.flags));
        try writer.writeIntLittle(u16, @enumToInt(self.compression_method));
        try writer.writeIntLittle(u16, self.last_mod_time);
        try writer.writeIntLittle(u16, self.last_mod_date);
        try writer.writeIntLittle(u32, self.crc32);
        try writer.writeIntLittle(u32, @truncate(u32, self.compressed_size));
        try writer.writeIntLittle(u32, @truncate(u32, self.uncompressed_size));
        try writer.writeIntLittle(u16, self.filename_len);
        try writer.writeIntLittle(u16, self.extra_len);
        try writer.writeIntLittle(u16, self.comment_len);
        try writer.writeIntLittle(u16, self.disk_number_start);
        try writer.writeIntLittle(u16, self.internal_attributes);
        try writer.writeIntLittle(u32, self.external_attributes);
        try writer.writeIntLittle(u32, @truncate(u32, self.local_offset));
    }

    // we only check the fields we actually use, the rest we don't care about
    pub fn needs64(self: CentralDirectoryRecord) bool {
        return self.compressed_size == 0xffffffff or
            self.uncompressed_size == 0xffffffff or
            self.local_offset == 0xffffffff;
    }
};

pub const EndOfCentralDirectory64Record = struct {
    pub const signature = 0x06064b50;

    size: u64,
    version_made: u16,
    version_needed: u16,
    disk_number: u32 = 0,
    disk_central: u32 = 0,
    num_entries_disk: u64,
    num_entries_total: u64,
    directory_size: u64,
    directory_offset: u64,

    pub fn read(reader: anytype) !EndOfCentralDirectory64Record {
        const sig = try reader.readIntLittle(u32);
        if (sig != signature) return error.InvalidSignature;

        var record: EndOfCentralDirectory64Record = undefined;

        var buf: [52]u8 = undefined;
        const nread = try reader.readAll(&buf);
        if (nread == 0) return error.EndOfStream;

        record.size = mem.readIntLittle(u64, buf[0..8]);
        record.version_made = mem.readIntLittle(u16, buf[8..10]);
        record.version_needed = mem.readIntLittle(u16, buf[10..12]);
        record.disk_number = mem.readIntLittle(u32, buf[12..16]);
        record.disk_central = mem.readIntLittle(u32, buf[16..20]);
        record.num_entries_disk = mem.readIntLittle(u64, buf[20..28]);
        record.num_entries_total = mem.readIntLittle(u64, buf[28..36]);
        record.directory_size = mem.readIntLittle(u64, buf[36..44]);
        record.directory_offset = mem.readIntLittle(u64, buf[44..52]);

        return record;
    }

    pub fn write(self: EndOfCentralDirectory64Record, writer: anytype) !void {
        try writer.writeIntLittle(u32, signature);
        try writer.writeIntLittle(u64, self.size);
        try writer.writeIntLittle(u16, self.version_made);
        try writer.writeIntLittle(u16, self.version_needed);
        try writer.writeIntLittle(u32, self.disk_number);
        try writer.writeIntLittle(u32, self.disk_central);
        try writer.writeIntLittle(u64, self.num_entries_disk);
        try writer.writeIntLittle(u64, self.num_entries_total);
        try writer.writeIntLittle(u64, self.directory_size);
        try writer.writeIntLittle(u64, self.directory_offset);
    }
};

pub const EndOfCentralDirectory64Locator = struct {
    pub const signature = 0x07064b50;

    disk_number: u32 = 0,
    offset: u64,
    num_disks: u32 = 1,

    pub fn read(reader: anytype) !EndOfCentralDirectory64Locator {
        // signature is consumed by the search algorithm

        var locator: EndOfCentralDirectory64Locator = undefined;

        var buf: [16]u8 = undefined;
        const nread = try reader.readAll(&buf);
        if (nread == 0) return error.EndOfStream;

        locator.disk_number = mem.readIntLittle(u32, buf[0..4]);
        locator.offset = mem.readIntLittle(u64, buf[4..12]);
        locator.num_disks = mem.readIntLittle(u32, buf[12..16]);

        return locator;
    }

    pub fn write(self: EndOfCentralDirectory64Locator, writer: anytype) !void {
        try writer.writeIntLittle(u32, signature);
        try writer.writeIntLittle(u32, self.disk_number);
        try writer.writeIntLittle(u64, self.offset);
        try writer.writeIntLittle(u32, self.num_disks);
    }
};

pub const EndOfCentralDirectoryRecord = struct {
    pub const signature = 0x06054b50;

    disk_number: u16 = 0,
    disk_central: u16 = 0,
    entries_on_disk: u16,
    entries_total: u16,
    directory_size: u32,
    directory_offset: u32,
    comment_length: u16 = 0,

    pub fn read(reader: anytype) !EndOfCentralDirectoryRecord {
        // signature is consumed by the search algorithm

        var record: EndOfCentralDirectoryRecord = undefined;

        var buf: [18]u8 = undefined;
        const nread = try reader.readAll(&buf);
        if (nread == 0) return error.EndOfStream;

        record.disk_number = mem.readIntLittle(u16, buf[0..2]);
        record.disk_central = mem.readIntLittle(u16, buf[2..4]);
        record.entries_on_disk = mem.readIntLittle(u16, buf[4..6]);
        record.entries_total = mem.readIntLittle(u16, buf[6..8]);
        record.directory_size = mem.readIntLittle(u32, buf[8..12]);
        record.directory_offset = mem.readIntLittle(u32, buf[12..16]);
        record.comment_length = mem.readIntLittle(u16, buf[16..18]);

        return record;
    }

    pub fn write(self: EndOfCentralDirectoryRecord, writer: anytype) !void {
        try writer.writeIntLittle(u32, signature);
        try writer.writeIntLittle(u16, self.disk_number);
        try writer.writeIntLittle(u16, self.disk_central);
        try writer.writeIntLittle(u16, self.entries_on_disk);
        try writer.writeIntLittle(u16, self.entries_total);
        try writer.writeIntLittle(u32, self.directory_size);
        try writer.writeIntLittle(u32, self.directory_offset);
        try writer.writeIntLittle(u16, self.comment_length);
    }

    // we only check the fields we actually use, the rest we don't care about
    pub fn needs64(self: EndOfCentralDirectoryRecord) bool {
        return self.directory_size == 0xffffffff or
            self.directory_offset == 0xffffffff or
            self.entries_total == 0xffff;
    }
};

pub const ExtraFieldZip64 = struct {
    uncompressed: ?u64 = null,
    compressed: ?u64 = null,
    offset: ?u64 = null,

    pub fn present(self: ExtraFieldZip64) bool {
        return !(self.uncompressed == null and self.compressed == null and self.offset == null);
    }

    pub fn length(self: ExtraFieldZip64) u16 {
        if (!self.present()) return 0;

        var size: u16 = 4;

        if (self.uncompressed != null) size += 8;
        if (self.compressed != null) size += 8;
        if (self.offset != null) size += 8;

        return size;
    }

    pub fn write(self: ExtraFieldZip64, writer: anytype) !void {
        if (!self.present()) return;

        try writer.writeIntLittle(u16, 0x0001);
        try writer.writeIntLittle(u16, self.length() - 4);

        if (self.uncompressed) |num| {
            try writer.writeIntLittle(u64, num);
        }

        if (self.compressed) |num| {
            try writer.writeIntLittle(u64, num);
        }

        if (self.offset) |num| {
            try writer.writeIntLittle(u64, num);
        }
    }
};
