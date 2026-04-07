/*
Thanks Jai Discord.

I upgraded the ktx loading code to support ktx2 files, and added support for ASTC 6x6 compressed textures.
- kevinw, 2025-10-010
*/

// Limited support for loading ktx images
//
// For full support you might want to use libktx (https://github.com/KhronosGroup/KTX-Software)
// Or, if you just want to handle the Basis Universal "super compression", you might want to use basisu directly
// (https://github.com/BinomialLLC/basis_universal). (Note that libktx uses basisu to handle transcoding super compresssed
// images).
//
// Spec: https://registry.khronos.org/KTX/specs/2.0/ktxspec.v2.html
//
// Someone from beta has now made bindings for libtx - https://github.com/wrapperup/jai-libktx

// NOTE(Charles): Why? The controller models returned by XR_FB_RENDER_MODEL gives us ktx2 images using Basis Universal
// super compression. I don't want to introduce dependency on one of the above libraries, but I do want to use the
// images. So I have used the ktx command line tool to transcode the images to a format I can directly upload to gpu
// (ASTC), and this is the code to read ktx2 files and create textures from them in this specific use case.
// The command to transcode was ~ `ktx transcode --target astc <input_name>.ktx2 <output_name>.ktx2`
//
/*

Notes about KTX:

After the header and the key/value data area, the actual image data follows.
Each image starts with a 4-byte "imageSize" value indicating the number of bytes of image data follow.
(For cube-maps, this value appears only after first image; the remaining 5 images are all of equal size.)
If the size of an image is not a multiple of 4, then it is padded to the next multiple of 4.
Note that this padding is NOT included in the "imageSize" field.
In a cubemap, the padding appears after each face note that in a 2D/3D texture, padding does
NOT appear between the lines/planes of the texture!

In a KTX file, there may be multiple images; they are organized as follows:

For each mipmap_level in numberOfMipmapLevels
	UInt32 imageSize;
	For each array_element in numberOfArrayElements
	* for each face in numberOfFaces
		* for each z_slice in pixelDepth
			* for each row or row_of_blocks in pixelHeight
				* for each pixel or block_of_pixels in pixelWidth
					Byte data[format-specific-number-of-bytes]
				* end
			* end
		*end
		Byte cubePadding[0-3]
	*end
	Byte mipPadding[3 - ((imageSize+ 3) % 4)]
*end
*/

Image_Descriptor :: struct {
    image_data: string;
    pixelWidth: u32;
    pixelHeight: u32;
    imageDataSizeInBytes: s64;
    bytesPerPixel: s32;
    pixelFormat: MTLPixelFormat = 0;
    faceCount: u32 = 1;
    levels: [..]struct {
        fileOffset: s64;
        sizeInBytes: s64;
        bytesPerRow: s64;
        bytesPerImage: s64;
        size: IntSize;
    };
    resourcePath: string;
    compressed: bool;
}

IntSize :: struct {
    width:  int;
    height: int;
    depth:  int = 1;
}

// As a string this is "«KTX 20»\r\n\x1A\n", however the double angle quotes get encoded as two bytes doing direct string
// conversion, so sticking with byte array!
KTX_FIRST_FIVE_BYTES :: u8.[0xAB, 0x4B, 0x54, 0x58, 0x20];
KTX1_FILE_IDENTIFIER :: u8.[0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A];
KTX2_FILE_IDENTIFIER :: u8.[0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A];
#assert KTX1_FILE_IDENTIFIER.count == 12;
#assert KTX2_FILE_IDENTIFIER.count == 12;

// Parse the header and return a struct describing mipmap levels and byte offsets for the images in the given KTX file.
ktx_load_descriptor :: (file_bytes: string, verbose: bool = false) -> bool, Image_Descriptor {
    if file_bytes.count < KTX1_FILE_IDENTIFIER.count {
        log_error("Error loading KTX file: size too short");
        return false, .{};
    }

    if memcmp(file_bytes.data, KTX1_FILE_IDENTIFIER.data, KTX1_FILE_IDENTIFIER.count) == 0 {
        ok, result := ktx1_load_from_memory(file_bytes, verbose);
        return ok, result;
    } else if memcmp(file_bytes.data, KTX2_FILE_IDENTIFIER.data, KTX2_FILE_IDENTIFIER.count) == 0 {
        ok, result := ktx2_load_from_memory(file_bytes, verbose);
        return ok, result;
    } else {
        log_error("Could not recognize KTX1 or KTX2 headers");
        return false, .{};
    }
}

ktx1_load_from_memory :: (file_bytes: string, verbose: bool) -> bool, Image_Descriptor {
    if verbose log("loading % bytes of ktx1", file_bytes.count);
    cursor := file_bytes;
    original_cursor := cursor;

    KTX1_Header :: struct {
        identifier: [12]u8;
        endianness: u32;
        glType: u32;
        glTypeSize: u32;
        glFormat: u32;
        glInternalFormat: u32;
        glBaseInternalFormat: u32;
        pixelWidth: u32;
        pixelHeight: u32;
        pixelDepth: u32;
        numberOfArrayElements: u32;
        numberOfFaces: u32;
        numberOfMipmapLevels: u32;
        bytesOfKeyValueData: u32;
    };

    header := cast(*KTX1_Header)cursor.data;
    for header.identifier  assert(it == KTX1_FILE_IDENTIFIER[it_index]);

    using result: Image_Descriptor;
    image_data = file_bytes;
    pixelWidth = header.pixelWidth;
    pixelHeight = header.pixelHeight;
    faceCount = header.numberOfFaces;
    cursor.data += size_of(KTX1_Header);
    bytes_read: s64 = 0;
    while bytes_read < header.bytesOfKeyValueData {
        kvCount: u32 = read_u32(*cursor);
        print("kvCount: %\n", kvCount);

        if kvCount & 0x03 { // Align to 4 bytes boundary.
            kvCount = cast(u32)((kvCount + 0x04) & ~0x03);
        }

        buffer: [..]u8;
        buffer.allocator = temp;
        array_resize(*buffer, kvCount);

        read_bytes_into(*cursor, buffer, kvCount);

        // read the kv pair separated by \0
        values: [2][..]u8;
        vindex := 0;
        for c: buffer {
            if !c vindex +=1;
            if vindex > 1 break;
            if c array_add(*values[vindex], c);
        }

        key   := string.{values[0].count, values[0].data};
        value := string.{values[1].count, values[1].data};
        log("K: %, V: %", key, value);

        bytes_read += 4 + kvCount;
    }
    assert(bytes_read == header.bytesOfKeyValueData);

    GL_COMPRESSED_RGBA_ASTC_4x4_KHR :: 0x93B0;
    GL_COMPRESSED_RGBA_ASTC_6x6_KHR :: 0x93B4;
    GL_RGBA8 :: 0x8058;
    GL_SRGB8_ALPHA8 :: 0x8C43;
    block_dim: s64 = 1;

    // Read mipmap sizes and offsets.
    if header.glInternalFormat == {
        case GL_COMPRESSED_RGBA_ASTC_4x4_KHR;
            pixelFormat = .ASTC_4x4_sRGB;
            block_dim = 4;
            bytesPerPixel = 1;
            compressed = true;
        case GL_COMPRESSED_RGBA_ASTC_6x6_KHR;
            pixelFormat = .ASTC_6x6_LDR;
            block_dim = 6;
            bytesPerPixel = 1;
            compressed = true;
        case GL_RGBA8;
            pixelFormat = .RGBA8Unorm;
            bytesPerPixel = 4;
            compressed = false;
        case GL_SRGB8_ALPHA8;
            pixelFormat = .RGBA8Unorm_sRGB;
            bytesPerPixel = 4;
            compressed = false;
        case;
            assert(false, "unhandled glInternalFormat in ktx1 texture: %", header.glInternalFormat);
        }

    assert(pixelFormat != 0);
    imageDataSizeInBytes = 0;
    // record the offset and size of each mipmap level
    for level: 0..header.numberOfMipmapLevels-1 {
        levelSizeInBytes: u32 = read_u32(*cursor);
        levelSize := IntSize.{ width = header.pixelWidth >> level, height = header.pixelHeight >> level, depth = 1 };

        // 4 byte boundary
        if levelSizeInBytes & 0x03 levelSizeInBytes = (levelSizeInBytes + 0x04) & 0x03;
        // update the total amount of the image and get the current file offset.
        imageDataSizeInBytes += levelSizeInBytes;
        levelFileOffset := cursor.data - original_cursor.data;
        advance(*cursor, levelSizeInBytes); // move forward the number of bytes for the image data to get to the next mipmap level.

        // Record data sizes based on ASTC 4x4 block compression or bytesPerPixel
        bytesPerRow: s64;
        bytesPerImage: s64;
        if compressed {
            blocks_x := max((cast(s64) levelSize.width + block_dim - 1) / block_dim, cast(s64) 1);
            blocks_y := max((cast(s64) levelSize.height + block_dim - 1) / block_dim, cast(s64) 1);
            bytesPerRow = blocks_x * 16;
            bytesPerImage = bytesPerRow * blocks_y;
        } else {
            bytesPerRow = cast(s64)max(levelSize.width * bytesPerPixel, 4);
            bytesPerImage = bytesPerRow * cast(s64) max(levelSize.height, 1);
        }
        array_add(*result.levels, .{
            fileOffset = levelFileOffset,
            sizeInBytes = levelSizeInBytes,
            bytesPerRow = bytesPerRow,
            bytesPerImage = bytesPerImage,
            size = levelSize,
        });
    }
    return true, result;
}

// @Cleanup Handle errors!
ktx2_load_from_memory :: (file_bytes: string, verbose: bool) -> bool, Image_Descriptor {
    if verbose log("loading % bytes of ktx2", file_bytes.count);
    cursor := file_bytes;

    KTX2_Header :: struct {
        identifier: [12] u8;
        vkFormat: u32;
        typeSize: u32;
        pixelWidth: u32;
        pixelHeight: u32;
        pixelDepth: u32;
        layerCount: u32;
        faceCount: u32;
        levelCount: u32;
        supercompressionScheme: u32;
    }

    KTX2_Index :: struct {
        dfdByteOffset: u32;
        dfdByteLength: u32;
        kvdByteOffset: u32;
        kvdByteLength: u32;
        sgdByteOffset: u64;
        sgdByteLength: u64;
    }

    header := cast(*KTX2_Header) cursor.data;
    advance(*cursor, size_of(KTX2_Header));
    for header.identifier  assert(it == KTX2_FILE_IDENTIFIER[it_index]);
    if verbose print("header:\n%\n", formatStruct(header));

    // "Limited support"!
    assert(header.vkFormat != 0, "vkFormat is %", header.vkFormat);               // No super compression
    assert(header.supercompressionScheme == 0, "supercompressionScheme is %", header.supercompressionScheme); //

    assert(header.typeSize == 1);
    assert(header.pixelDepth == 0);
    assert(header.layerCount == 0);

    using result: Image_Descriptor;
    image_data = file_bytes;

    pixelWidth = header.pixelWidth;
    pixelHeight = header.pixelHeight;
    faceCount = header.faceCount;

    VK_FORMAT_ASTC_6x6_SRGB_BLOCK :: 166;
    VK_FORMAT_ASTC_4x4_SRGB_BLOCK :: 158;
    VK_FORMAT_R8G8B8A8_UNORM :: 37;
    VK_FORMAT_R8G8B8A8_SRGB :: 43;

    pixels_per_block: u64 = 0;

    if header.vkFormat == {
        case VK_FORMAT_ASTC_6x6_SRGB_BLOCK;
            pixelFormat = .ASTC_6x6_LDR;
            pixels_per_block = 6;
            compressed = true;
        case VK_FORMAT_ASTC_4x4_SRGB_BLOCK;
            pixelFormat = .ASTC_4x4_LDR;
            pixels_per_block = 4;
            bytesPerPixel = 1;
            compressed = true;
        case VK_FORMAT_R8G8B8A8_UNORM;
            pixelFormat = .RGBA8Unorm;
            bytesPerPixel = 4;
            compressed = false;
        case VK_FORMAT_R8G8B8A8_SRGB;
            pixelFormat = .RGBA8Unorm_sRGB;
            bytesPerPixel = 4;
            compressed = false;
        case;
            assert(false, "unhandled vkFormat in ktx2 texture: %", header.vkFormat);
    }

    index := cast(*KTX2_Index)cursor.data;
    cursor.data += size_of(KTX2_Index);
    if verbose print("index:\n%\n", formatStruct(index));

    // Level Index
    KTX_Level_Index :: struct {
        byteOffset: u64;
        byteLength: u64;
        uncompressedByteLength: u64;
    }

    // read all mipmap levels
    for * lvl, level: []KTX_Level_Index.{ header.levelCount, xx cursor.data } {
        levelSize := IntSize.{ pixelWidth >> level, pixelHeight >> level, 1 };

        advance(*cursor, size_of(KTX_Level_Index));
        assert(lvl.byteLength == lvl.uncompressedByteLength); // Until we support supercompression

        bytesPerRow: int;
        if compressed  {
            assert(pixels_per_block != 0);
            bytesPerRow = cast(s64)max(Math.ceil(cast(float)levelSize.width / cast(float)pixels_per_block) * 16, 16);
        } else {
            bytesPerRow = cast(s64)max(levelSize.width * bytesPerPixel, 4);
        }
        array_add(*result.levels, .{
            fileOffset = xx lvl.byteOffset,
            sizeInBytes = xx lvl.byteLength,
            bytesPerRow = bytesPerRow,
            bytesPerImage = bytesPerRow * cast(s64)levelSize.height,
            size = levelSize,
        });
    }

    return true, result;

}

#scope_file

read_u32 :: inline (s: *string) -> u32 {
    assert(s.count >= 4);
    result := (cast(*u32)s.data).*;
    advance(s, 4);
    return result;
}

read_bytes_into :: inline (s: *string, buffer: []u8, count: s64) {
    assert(buffer.count >= count);
    assert(s.count >= count);
    memcpy(buffer.data, s.data, count);
    advance(s, count);
}


#import "Hash_Table";
#import "Basic";
#import "Bit_Operations";
#import "Metal";
Math :: #import "Math";
