#import "Basic";
#import "Compiler";
#import "String";
#import "Flat_Pool";

#scope_module

Ply_Format :: enum {
    UNKNOWN;
    ASCII;
    BINARY_LITTLE_ENDIAN;
    BINARY_BIG_ENDIAN;
}

Ply_Property_Type :: enum u8 #specified {
    UNKNOWN :: 0; // 1 | s8
    CHAR    :: 1; // 1 | s8
    UCHAR   :: 2; // 1 | u8
    SHORT   :: 3; // 2 | s16
    USHORT  :: 4; // 2 | u16
    INT     :: 5; // 4 | s32
    UINT    :: 6; // 4 | u32
    FLOAT   :: 7; // 4 | float32
    DOUBLE  :: 8; // 8 | float64
}

str_to_property_type :: (str: string) -> Ply_Property_Type {
    if str == {
        case "char";   return .CHAR;
        case "uchar";  return .UCHAR;
        case "short";  return .SHORT;
        case "ushort"; return .USHORT;
        case "int";    return .INT;
        case "uint";   return .UINT;
        case "float";  return .FLOAT;
        case "double"; return .DOUBLE;
        case; {
            log_error("Invalid property type: %", str);
            return .UNKNOWN;
        }
    }
}

size_of_property_type :: (type: Ply_Property_Type) -> u32 {
    if type == {
        case .CHAR;   return size_of(s8);
        case .UCHAR;  return size_of(u8);
        case .SHORT;  return size_of(s16);
        case .USHORT; return size_of(u16);
        case .INT;    return size_of(s32);
        case .UINT;   return size_of(u32);
        case .FLOAT;  return size_of(float32);
        case .DOUBLE; return size_of(float64);
        case; {
            log_error("Invalid property type: %", type);
            return 0;
        }
    }
}

parse_header :: (data_str: string, result: *Ply_Data) -> format: Ply_Format = .UNKNOWN, ok: bool = true {
    lines := split(data_str, "\n");
    format: Ply_Format = .UNKNOWN;

    if lines[0] != "ply" {
        log_error("Invalid ply data");
        return ok = false;
    }

    has_end_header := false;
    for 1..cast(u32)lines.count-1 {
        tokens := split(lines[it], " ");

        if tokens[0] == {
            case "comment"; {
                array_add(*result.comments, join(..array_view(tokens, 1), " "));
            }
            case "element"; {
                element: Ply_Element = .{
                    name = tokens[1],
                    size = xx string_to_int(tokens[2]),
                };
                array_add(*result.elements, element);
            }
            case "format"; {
                if tokens[1] == {
                    case "ascii"; {
                        format = .ASCII;
                    }
                    case "binary_little_endian"; {
                        format = .BINARY_LITTLE_ENDIAN;
                    }
                    case "binary_big_endian"; {
                        format = .BINARY_BIG_ENDIAN;
                    }
                }
            }
            case "property"; {
                parent := peek_pointer(result.elements);
                if parent == null {
                    log_error("Invalid property declaration, line: %", it);
                    return ok = false;
                }

                if tokens[1] != "list" {
                    property: Ply_Property = .{
                        name = tokens[2],
                        type = str_to_property_type(tokens[1]),
                    };

                    if property.type == .UNKNOWN {
                        log_error("Invalid property type: %, line %", tokens[1], it);
                        return ok = false;
                    }

                    array_add(*parent.properties, property);
                } else {
                    property: Ply_Property = .{
                        name = tokens[4],
                        type = str_to_property_type(tokens[3]),
                    };
                    parent.stride = 0xFFFFFFFFFFFFFFFF;
                }
            }
            case "end_header"; {
                has_end_header = true;
                break;
            }
            case; {
                log_error("Invalid header line: %", it);
                return ok = false;
            }
        }
    }

    if !has_end_header {
        log_error("Invalid ply header, doesn't contain `end_header`");
        return ok = false;
    }

    return format, ok = true;
}

allocate_for_elements :: (result: *Ply_Data) {
    for *e: result.elements {
        if e.stride == 0xFFFFFFFFFFFFFFFF {
            e.data = cast(*u8) get(*result.mem_pool, cast(s64)(size_of(u64) * e.size));
            continue;
        }

        for *p: e.properties {
            p_size := size_of_property_type(p.type);
            e.stride += p_size;
        }
        e.data = cast(*u8) get(*result.mem_pool, cast(s64)(e.stride * e.size));
    }
}

#scope_export

Ply_Data :: struct {
    comments: [..] string;
    elements: [..] Ply_Element;

    mem_pool: Flat_Pool;
}

Ply_Element :: struct {
    name: string;
    properties: [..] Ply_Property;
    data: *u8 = null;
    size: u64 = 0;
    stride: u64 = 0; // 0xFFFFFFFFFFFFFFFF signifies list
}

Ply_Property :: struct {
    name: string;
    type: Ply_Property_Type;
}

ply_from_buffer :: (data: [..] u8) -> result: Ply_Data = .{}, ok: bool = true {
    result: Ply_Data;

    new_context := context;
    allocator: Allocator;
    allocator.proc = flat_pool_allocator_proc;
    allocator.data = *result.mem_pool;
    new_context.allocator = *allocator;

    push_context new_context {
        END_HEADER_STR :: "\nend_header\n";
        END_HEADER_LEN :: #insert #run () -> string {
            return tprint("%;", END_HEADER_STR.count);
        }();

        data_str: string = ---;
        data_str.data = data.data;
        data_str.count = data.count;

        end_header_index := find_index_from_left(data_str, END_HEADER_STR);
        if end_header_index == -1 {
            log_error("Invalid ply data, doesn't contain `end_header`");
            return ok = false;
        }

        header := slice(data_str, 0, end_header_index + END_HEADER_LEN);
        format, ok := parse_header(header, *result);
        if !ok {
            return ok = false;
        }

        allocate_for_elements(*result);
        // body := array_view(
        //     data, end_header_index + END_HEADER_LEN,
        //     data.count - end_header_index - END_HEADER_LEN);
        //
        // test_str: string = ---;
        // test_str.data = body.data;
        // test_str.count = body.count;
        // log("\n\n\n\nbody:\n%", test_str);
    }

    log("%", result);

    return ok = true;
}

ply_from_str :: inline (data: string) -> result: Ply_Data = .{}, ok: bool = true {
    buffer: [..] u8;
    buffer.data = data.data;
    buffer.count = data.count;

    return ply_from_buffer(buffer);
}

ply_from_file :: (path: string) -> result: Ply_Data = .{}, ok: bool = true {
    file_data, ok := read_entire_file(path);
    if !ok {
        log_error("Failed to read file: %", path);
        return false;
    }
    defer free(file);

    return ply_from_str(file_data);
}

// get_property(element: Ply_Element, property_name: string) -> $T, bool;
//
// get_list_property(element: Ply_Element, property_name: string) -> [..] $T, bool;
//
// get_element(data: Ply_Data, element: string) -> PlyElement, bool;

release :: (using ply_data: Ply_Data) {
    fini(*mem_pool);
}
