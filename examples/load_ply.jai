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
    data, ok := ply_from_str(TEST_DATA);
    if !ok {
        log_error("Failed to load ply data");
        exit(1);
    }

    log("data:\n%", data);

    release(data);
}
