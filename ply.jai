#import "Basic";
#import "Compiler";
#import "File";
#import "String";
#import "Bit_Operations";
#import "Flat_Pool";

// Only allocating 32kb by default, as this only contains elements, properties, strings,
// comments, and other metadata. The actual data is allocated separately.
#module_parameters (DEFAULT_MEMORY_POOL_SIZE := 32 * 1024);

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

default_allocator :: Allocator.{runtime_support_default_allocator_proc, null};

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

ascii :: (num: u8) -> string #expand {
    return .{1, *num};
}

next_token :: (str: string, cursor: *s64) -> string {
    result: string = ---;
    result.data = str.data + <<cursor;
    result.count = 0;

    if <<cursor >= str.count {
        <<cursor += 1;
        return result;
    }

    for (<<cursor)..(str.count-1) {
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

    if result.count == 0 {
        result.count = str.count - <<cursor;
    }

    <<cursor += result.count + 1;
    if <<cursor < str.count {
        while str[<<cursor] == #char " " || str[<<cursor] == #char "\n" {
            <<cursor += 1;
        }
    }

    return result;
}

allocate_for_elements :: (result: *Ply_Data) {
    for *e: result.elements {
        if e.stride == ~cast(u64)0 {
            e.data = cast(*u8) alloc(cast(s64)(size_of(u64) * e.count * 2),, default_allocator);
            continue;
        }

        for *p: e.properties {
            p_size := size_of_property_type(p.type);
            p.offset = e.stride;
            e.stride += p_size;
        }
        e.data = cast(*u8) alloc(cast(s64)(e.stride * e.count),, default_allocator);
    }
}

parse_header :: (data_str: string, result: *Ply_Data) -> format: Ply_Format = .UNKNOWN, ok: bool = true {
    format: Ply_Format = .UNKNOWN;

    cursor: s64 = 0;
    token := next_token(data_str, *cursor);
    if token != "ply" {
        log_error("Invalid ply data");
        return ok = false;
    }

    has_end_header := false;
    token = next_token(data_str, *cursor);
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
                if next_token(data_str, *cursor) == {
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

                _version := next_token(data_str, *cursor);
            }
            case "element"; {
                element: Ply_Element = .{
                    name = copy_string(next_token(data_str, *cursor)),
                    count = string_to_int(next_token(data_str, *cursor), T = u64),
                };
                array_add(*result.elements, element);
            }
            case "property"; {
                parent := peek_pointer(result.elements);
                if parent == null {
                    log_error("Invalid property declaration, type %, property: %",
                        next_token(data_str, *cursor),
                        next_token(data_str, *cursor));
                    return ok = false;
                }

                type_token := next_token(data_str, *cursor);
                if type_token != "list" {
                    property: Ply_Property = .{
                        type = str_to_property_type(type_token),
                        name = copy_string(next_token(data_str, *cursor)),
                    };

                    if property.type == .UNKNOWN {
                        log_error("Invalid property type: %", property.name);
                        return ok = false;
                    }

                    array_add(*parent.properties, property);
                } else {
                    _list_count_type := next_token(data_str, *cursor);

                    property: Ply_Property = .{
                        type = str_to_property_type(next_token(data_str, *cursor)),
                        name = copy_string(next_token(data_str, *cursor)),
                    };
                    parent.stride = ~cast(u64)0; // denotes list

                    if property.type == .UNKNOWN {
                        log_error("Invalid property type: %", property.name);
                        return ok = false;
                    }

                    array_add(*parent.properties, property);
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

        token = next_token(data_str, *cursor);
    }

    if !has_end_header {
        log_error("Invalid ply header, doesn't contain `end_header` 2");
        return ok = false;
    }

    return format, ok = true;
}

elements_data_to_little_endian :: (result: *Ply_Data) {
    byte_swap_in_place :: (type: Ply_Property_Type, location: *u8) {
        if type == {
            case .CHAR; {
                value: *s8 = cast(*s8)(location);
                byte_swap_in_place(value);
            }
            case .UCHAR; {
                value: *u8 = cast(*u8)(location);
                byte_swap_in_place(value);
            }
            case .SHORT; {
                value: *s16 = cast(*s16)(location);
                byte_swap_in_place(value);
            }
            case .USHORT; {
                value: *u16 = cast(*u16)(location);
                byte_swap_in_place(value);
            }
            case .INT; {
                value: *s32 = cast(*s32)(location);
                byte_swap_in_place(value);
            }
            case .UINT; {
                value: *u32 = cast(*u32)(location);
                byte_swap_in_place(value);
            }
            case .FLOAT; {
                value: *float32 = cast(*float32)(location);
                byte_swap_in_place(value);
            }
            case .DOUBLE; {
                value: *float64 = cast(*float64)(location);
                byte_swap_in_place(value);
            }
        }

    }

    for *e : result.elements {
        if e.stride == ~cast(u64)0 {
            for c : 0..e.count-1 {
                // list_size: u8 = <<cast(*u8)(e.data + (size_of(s64) * c * 2));
                // for 0..list_size-1 {
                //     for *p : e.properties {
                //         total_offset := e.stride * c + p.offset;
                //
                //         byte_swap_in_place(p.type, e.data + total_offset);
                //     }
                // }
                // list_size: u8 = <<cast(*u8)(e.data + (size_of(s64) * c * 2) + size_of(s64));
                // log("list_size: %", list_size);
            }
        } else {
            for c : 0..e.count-1 {
                for *p : e.properties {
                    total_offset := e.stride * c + p.offset;

                    byte_swap_in_place(p.type, e.data + total_offset);
                }
            }
        }
    }
}

parse_body_binary :: (body: [] u8, result: *Ply_Data) -> ok: bool = true {
    cursor: s64 = 0;
    for *e : result.elements {
        if e.stride == ~cast(u64)0 {
            p: *Ply_Property = *e.properties[0];
            for c : 0..e.count-1 {
                list_size: u8 = <<cast(*u8)(body.data + cursor);
                cursor += size_of(u8);
                buffer := cast(*u8) alloc(cast(s64)(size_of_property_type(p.type) * list_size),, default_allocator);
                memcpy(buffer, body.data + cursor, size_of_property_type(p.type) * list_size);
                cursor += size_of_property_type(p.type) * list_size;

                offset := (size_of(s64) * c * 2);
                memcpy(e.data + offset, *buffer, size_of(*u8));
                memcpy(e.data + offset + size_of(s64), *list_size, size_of(*u8));
            }
        } else {
            chunk_size: u64 = 0;
            for *p: e.properties {
                chunk_size += size_of_property_type(p.type);
            }
            chunk_size *= e.count;
            memcpy(e.data, body.data + cursor, xx chunk_size);

            cursor += xx chunk_size;
        }
    }

    return ok = true;
}

parse_body_ascii :: (body: [] u8, result: *Ply_Data) -> ok: bool = true {
    memcpy_to_data :: (type: Ply_Property_Type, token: string, location: *u8) {
        if type == {
            case .CHAR; {
                v := string_to_int(token, T = s8);
                memcpy(location, *v, size_of(s8));
            }
            case .UCHAR; {
                v := string_to_int(token, T = u8);
                memcpy(location, *v, size_of(u8));
            }
            case .SHORT; {
                v := string_to_int(token, T = s16);
                memcpy(location, *v, size_of(s16));
            }
            case .USHORT; {
                v := string_to_int(token, T = u16);
                memcpy(location, *v, size_of(u16));
            }
            case .INT; {
                v := string_to_int(token, T = s32);
                memcpy(location, *v, size_of(s32));
            }
            case .UINT; {
                v := string_to_int(token, T = u32);
                memcpy(location, *v, size_of(u32));
            }
            case .FLOAT; {
                v := string_to_float(token);
                memcpy(location, *v, size_of(float32));
            }
            case .DOUBLE; {
                v := string_to_float64(token);
                memcpy(location, *v, size_of(float64));
            }
        }
    }

    body_str: string = ---;
    body_str.data = body.data;
    body_str.count = ifx body[body.count-1] == #char "\n" then body.count - 1 else body.count;

    cursor: s64 = 0;

    for *e : result.elements {
        if e.stride == ~cast(u64)0 {
            p: *Ply_Property = *e.properties[0];
            for c : 0..e.count-1{
                list_size_token := next_token(body_str, *cursor);
                list_size: s64 = xx string_to_int(list_size_token, T = u8);

                buffer := cast(*u8) alloc(cast(s64)(size_of_property_type(p.type) * list_size),, default_allocator);
                for 0..list_size-1 {
                    token := next_token(body_str, *cursor);
                    memcpy_to_data(p.type, token, buffer + (size_of_property_type(p.type) * it));
                }

                offset := (size_of(s64) * c * 2);
                memcpy(e.data + offset, *buffer, size_of(*u8));
                memcpy(e.data + offset + size_of(s64), *list_size, size_of(*u8));
            }
        } else {
            total_stride: u64 = 0;
            for c : 0..e.count-1 {
                for *p : e.properties {
                    token := next_token(body_str, *cursor);
                    total_offset := total_stride + p.offset;

                    memcpy_to_data(p.type, token, e.data + total_offset);
                }
                total_stride += e.stride;
            }
        }
    }

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
    offset: u64 = 0;
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

        if format == {
            case .ASCII; {
                ok := parse_body_ascii(body, *result);
                if !ok {
                    log_error("Failed to parse body");
                    return ok = false;
                }
            }
            case .BINARY_LITTLE_ENDIAN; {
                ok := parse_body_binary(body, *result);
                if !ok {
                    log_error("Failed to parse body");
                    return ok = false;
                }
            }
            case .BINARY_BIG_ENDIAN; {
                ok := parse_body_binary(body, *result);
                if !ok {
                    log_error("Failed to parse body");
                    return ok = false;
                }

                elements_data_to_little_endian(*result);
            }
        }
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

// @temp makes use of the temp allocator
get_property :: (using element: Ply_Element, property_name: string, $T: Type) -> result: [] T = .{}, ok: bool = true {
    p: Ply_Property;
    for element.properties {
        if it.name == property_name {
            p = it;
            break;
        }
    }
    if p.name != property_name {
        log_error("Failed to find property: %", property_name);
        return ok = false;
    }

    result: [] T = ---;
    result.data = xx alloc(cast(s64)(size_of(T) * count),, temp);
    result.count = xx count;

    for 0..count-1 {
        total_offset := p.offset + (stride * it);
        value: *T = xx (element.data + total_offset);
        memcpy(result.data + it, value, size_of(T));
    }

    return result = result;
}

get_list_property :: (using element: Ply_Element, property_name: string, $T: Type) -> result: [][] T = .{}, ok: bool = true {
    p: Ply_Property;
    for element.properties {
        if it.name == property_name {
            p = it;
            break;
        }
    }
    if p.name != property_name {
        log_error("Failed to find property: %", property_name);
        return ok = false;
    }

    buffer := cast(*u8) alloc(cast(s64)(size_of([] T) * count),, temp);
    log("size: %", cast(s64)(size_of([] T)));
    for 0..count-1 {
        view: *[] T = xx (buffer + (size_of([] T) * it));
        offset := (size_of(s64) * it * 2);
        memcpy(*view.data, element.data + offset, size_of(*u8));
        memcpy(*view.count, element.data + offset + size_of(s64), size_of(s64));
    }

    result: [][] T = ---;
    result.data = xx buffer;
    result.count = xx count;

    return result = result;
}


get_element :: (data: Ply_Data, element: string) -> result: Ply_Element = .{}, ok: bool = true {
    for data.elements {
        if it.name == element {
            return result = it;
        }
    }

    return ok = false;
}

release :: (using ply_data: Ply_Data) {
    for *e: elements {
        if e.stride == ~cast(u64)0 {
            for 0..e.count-1 {
                buffer: *u8;
                memcpy(*buffer, e.data + (size_of(s64) * it * 2), size_of(*u8));
                free(buffer,, default_allocator);
            }
        }
        free(e.data);
    }

    fini(*mem_pool);
}
