# jai_ply

Simple ply parser written in jai.

This is mainly written for my own purposes, but feel free to use it if you find it useful.  
Only supports reading, but it does accept both ascii and binary, and also both little and big endian.  

Main limitation is in terms of how lists are handled. Most of ply models I have worked with have a separate element
for list properties, so this parser assumes that an element is either a list or a group of properties. This doesn't
fully align with the "spec", but it allows for trivial memory management, and surprisingly fast parsing.

In terms of performance it is able to parse [Lucy](https://graphics.stanford.edu/data/3Dscanrep/) (533MB) in less than
750ms, including converting from big endian to little endian.  
For other non mesh-like data, testing with the Lego (15.7MB) sample from the Blender samples, it takes less than 30ms to
parse the file.  
All of this in a AMD Ryzen 7 8845HS @ 5.14 GHz.

The buffers under each element are tightly packed, so you can copy them directly to to the GPU.  
The memory layout of the buffer is determined by the order in which they are declared in the header.

As for memory management, it makes use of a pool allocator for all the metadata of the ply file, and a separate
allocation per buffer for each element.  
Calling the release function will free all the memory allocated by the parser.

## Usage

To be able to import from your code you need to add this project as a directory under `modules` at the root of your
project.

I recommend using `jai_ply` as a git submodule, and simply rename it to `ply` under `modules`.

```bash
# from your root directory
mkdir -p modules
git submodule add https://github.com/lmariscal/jai_ply.git modules/ply
```

Then you can import it in your code like this:

```jai
#import "Basic";
#import "ply";

TEST_DATA := #string END
ply
format ascii 1.0
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
    // data, ok := ply_from_file("./model.ply");
    if !ok {
        log_error("Failed to load ply data");
        exit(1);
    }

    vertex, ok= := get_element(data, "vertex");
    if !ok {
        log_error("Failed to get vertex element");
        exit(1);
    }

    x, ok= := get_property(vertex, "x", float32);
    if !ok {
        log_error("Failed to get x property");
        exit(1);
    }

    log("x: %", x);

    release(data);
}
```
