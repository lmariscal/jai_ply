#import "Basic";
#import,dir "../";

TEST_DATA := #string END
ply
format ascii 1.0
comment made by Greg Turk
comment this file is a cube
element vertex 8
property float x
property float y
property float z
element face 6
property list uchar int vertex_index
end_header
0 3 0
0 0 1
0 1 1
0 1 0
1 0 0
1 0 1
1 1 1
1 1 0
4 0 1 2 3
4 7 6 5 4
4 0 4 5 1
4 1 5 6 2
4 2 6 7 3
4 3 7 4 0
END

main :: () {
    // data, ok := ply_from_str(TEST_DATA);
    // data, ok := ply_from_file("./lucy.ply");
    // data, ok := ply_from_file("./cube_ascii.ply");
    // data, ok := ply_from_file("./cube_bin.ply");
    // data, ok := ply_from_file("./dragon_vrip.ply");
    data, ok := ply_from_file("./lego.ply");
    if !ok {
        log_error("Failed to load ply data");
        exit(1);
    }

    log("data:\n%", data);
    log("size of mem pool: %mb", (data.mem_pool.address_limit - data.mem_pool.memory_base) / 1024 / 1024);
    log("size of mem pool: %kb", (data.mem_pool.address_limit - data.mem_pool.memory_base) / 1024);
    log("size of mem pool: %b", (data.mem_pool.address_limit - data.mem_pool.memory_base));
    log("actually used: %mb", (data.mem_pool.current_point - data.mem_pool.memory_base) / 1024 / 1024);
    log("actually used: %kb", (data.mem_pool.current_point - data.mem_pool.memory_base) / 1024);
    log("actually used: %b", (data.mem_pool.current_point - data.mem_pool.memory_base));

    vertex, ok= := get_element(data, "vertex");
    if !ok {
        log_error("Failed to get vertex element");
        exit(1);
    }

    vertex_y, ok= := get_property(vertex, "x", float32);
    if !ok {
        log_error("Failed to get y property");
        exit(1);
    }

    log("vertex_y: %", vertex_y);

    release(data);
}
