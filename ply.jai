#import "Basic";
#import "Compiler";
#import "File";
#import "String";
#import "Flat_Pool";

// Only allocating 4kb by default, as this only contains elements and property names,
// comments, and other metadata. The actual data is allocated separately.
#module_parameters (DEFAULT_MEMORY_POOL_SIZE := 4 * 1024);

#scope_module

Ply_Format :: enum {
    UNKNOWN;
    ASCII;
    BINARY_LITTLE_ENDIAN;
    BINARY_BIG_ENDIAN;
}

Ply_Property_Type :: enum u8 #specified {
    UNKNOWN :: 0; //
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

next_token :: (str: string, cursor: *s64, is_new_line: *bool) -> string {
    result: string = ---;
    result.data = str.data + <<cursor;

    for <<cursor..str.count {
        if str[it] == {
            case #char " "; {
                result.count = it - <<cursor;
                break;
            }
            case #char "\n"; {
                result.count = it - <<cursor;
                break;
            }
        }
    }

    <<cursor += result.count + 1;
    <<is_new_line = str[<<cursor - 1] == #char "\n";
    return result;
}

allocate_for_elements :: (result: *Ply_Data) {
    default_allocator :: Allocator.{runtime_support_default_allocator_proc, null};

    for *e: result.elements {
        if e.stride == ~cast(u64)0 {
            e.data = cast(*u8) alloc(cast(s64)(size_of(u64) * e.count),, default_allocator);
            log("allocated %mb for % elements, list", (cast(s64)(size_of(u64) * e.count)) / 1024 / 1024, e.count);
            continue;
        }

        for *p: e.properties {
            p_size := size_of_property_type(p.type);
            e.stride += p_size;
        }
        e.data = cast(*u8) alloc(cast(s64)(e.stride * e.count),, default_allocator);
        log("allocated %mb for % elements", (cast(s64)(e.stride * e.count)) / 1024 / 1024, e.count);
    }
}

parse_header :: (data_str: string, result: *Ply_Data) -> format: Ply_Format = .UNKNOWN, ok: bool = true {
    format: Ply_Format = .UNKNOWN;

    cursor: s64 = 0;
    is_new_line: bool = false;
    token := next_token(data_str, *cursor, *is_new_line);
    if token != "ply" || !is_new_line {
        log_error("Invalid ply data");
        return ok = false;
    }

    has_end_header := false;
    token = next_token(data_str, *cursor, *is_new_line);
    while cursor <= data_str.count {
        if token == {
            case "comment"; {
                count := 0;
                for cursor..data_str.count {
                    if data_str[it] == #char "\n" {
                        count = it - cursor;
                        break;
                    }
                }

                comment: string = copy_string(slice(data_str, cursor, count));
                cursor += count + 1;
                array_add(*result.comments, comment);
            }
            case "format"; {
                if next_token(data_str, *cursor, *is_new_line) == {
                    case "ascii"; {
                        format = .ASCII;
                    }
                    case "binary_little_endian"; {
                        format = .BINARY_LITTLE_ENDIAN;
                    }
                    case "binary_big_endian"; {
                        format = .BINARY_BIG_ENDIAN;
                    }
                    case; {
                        log_error("Invalid format: %", format);
                        return ok = false;
                    }
                }

                _version := next_token(data_str, *cursor, *is_new_line);
            }
            case "element"; {
                element: Ply_Element = .{
                    name = copy_string(next_token(data_str, *cursor, *is_new_line)),
                    count = string_to_int(next_token(data_str, *cursor, *is_new_line), T = u64),
                };
                array_add(*result.elements, element);
            }
            case "property"; {
                parent := peek_pointer(result.elements);
                if parent == null {
                    log_error("Invalid property declaration, type %, property: %",
                        next_token(data_str, *cursor, *is_new_line),
                        next_token(data_str, *cursor, *is_new_line));
                    return ok = false;
                }

                type_token := next_token(data_str, *cursor, *is_new_line);
                if type_token != "list" {
                    property: Ply_Property = .{
                        type = str_to_property_type(type_token),
                        name = copy_string(next_token(data_str, *cursor, *is_new_line)),
                    };

                    if property.type == .UNKNOWN {
                        log_error("Invalid property type: %", property.name);
                        return ok = false;
                    }

                    array_add(*parent.properties, property);
                } else {
                    _list_count_type := next_token(data_str, *cursor, *is_new_line);

                    property: Ply_Property = .{
                        type = str_to_property_type(next_token(data_str, *cursor, *is_new_line)),
                        name = copy_string(next_token(data_str, *cursor, *is_new_line)),
                    };
                    parent.stride = ~cast(u64)0; // denotes list
                }
            }
            case "end_header"; {
                has_end_header = true;
                break;
            }
            case; {
                log_error("Invalid header token: %", token);
                return ok = false;
            }
        }

        token = next_token(data_str, *cursor, *is_new_line);
    }

    if !has_end_header {
        log_error("Invalid ply header, doesn't contain `end_header` 2");
        return ok = false;
    }

    return format, ok = true;
}

parse_body_ascii :: (body: [] u8, result: *Ply_Data) -> ok: bool = true {
    body_str: string = ---;
    body_str.data = body.data;
    body_str.count = ifx body[body.count-1] == #char "\n" then body.count - 1 else body.count;

    log("body: %", body_str);
    // lines := split(body_str, "\n");
    // for lines {
    //     tokens := split(it, " ");
    //     // log("%", tokens);
    // }

    return ok = true;
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
    count: u64 = 0;
    stride: u64 = 0; // 0xFFFFFFFFFFFFFFFF signifies list
}

Ply_Property :: struct {
    name: string;
    type: Ply_Property_Type;
}

ply_from_buffer :: (data: [] u8) -> result: Ply_Data = .{}, ok: bool = true {
    result: Ply_Data;
    init(*result.mem_pool, DEFAULT_MEMORY_POOL_SIZE);

    new_context := context;
    allocator: Allocator;
    allocator.proc = flat_pool_allocator_proc;
    allocator.data = *result.mem_pool;
    new_context.allocator = *allocator;

    push_context new_context {
        END_HEADER_STR :: "\nend_header\n";

        data_str: string = ---;
        data_str.data = data.data;
        data_str.count = data.count;

        end_header_index := find_index_from_left(data_str, END_HEADER_STR);
        if end_header_index == -1 {
            log_error("Invalid ply data, doesn't contain `end_header` 1");
            return ok = false;
        }

        header := slice(data_str, 0, end_header_index + END_HEADER_STR.count);
        format, ok := parse_header(header, *result);
        if !ok {
            return ok = false;
        }

        allocate_for_elements(*result);

        log("format: %", format);

        body := array_view(
            data, end_header_index + END_HEADER_STR.count,
            data.count - end_header_index - END_HEADER_STR.count);

        // if format == .ASCII {
        //     ok := parse_body_ascii(body, *result);
        //     if !ok {
        //         log_error("Failed to parse body");
        //         return ok = false;
        //     }
        // }
    }

    return result, ok = true;
}

ply_from_str :: inline (data: string) -> result: Ply_Data = .{}, ok: bool = true {
    buffer: [] u8 = ---;
    buffer.data = data.data;
    buffer.count = data.count;

    return ply_from_buffer(buffer);
}

ply_from_file :: (path: string) -> result: Ply_Data = .{}, ok: bool = true {
    file, ok := file_open(path);
    if !ok {
        log_error("Failed to open file: %", path);
        return ok = false;
    }
    defer file_close(*file);

    length := file_length(file);
    buffer := cast(*u8) alloc(length);
    defer free(buffer);

    success := file_read(file, buffer, length);
    if !success {
        log_error("Failed to read file: %", path);
        return ok = false;
    }

    buffer_view: [] u8 = ---;
    buffer_view.data = buffer;
    buffer_view.count = length;
    return ply_from_buffer(buffer_view);
}

// get_property(element: Ply_Element, property_name: string) -> $T, bool;
//
// get_list_property(element: Ply_Element, property_name: string) -> [..] $T, bool;
//
// get_element(data: Ply_Data, element: string) -> PlyElement, bool;

release :: (using ply_data: Ply_Data) {
    for *e: elements {
        free(e.data);
    }

    fini(*mem_pool);
}
