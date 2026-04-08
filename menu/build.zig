const std = @import("std");
const builtin = @import("builtin");
const ResolvedTarget = std.Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;
const Compile = std.Build.Step.Compile;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const src_module = b.addModule("catalog", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "catalog",
        .root_module = src_module,
    });

    addImports(b, target, optimize, exe);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the service");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
}

fn addImports(b: *std.Build, target: ResolvedTarget, optimize: OptimizeMode, exe: *Compile) void {
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("httpz", httpz.module("httpz"));

    exe.root_module.link_libc = false;
    exe.root_module.addIncludePath(b.path("mongo_libs/include/bson-2.2.3"));
    exe.root_module.addIncludePath(b.path("mongo_libs/include/mongoc-2.2.3"));
    exe.addLibraryPath(b.path("mongo_libs/lib"));
    switch (builtin.target.os.tag) {
        .macos => {
            // Testing on MacOS
            exe.root_module.addObjectFile(b.path("mongo_libs/lib/libbson2.dylib"));
            exe.root_module.addObjectFile(b.path("mongo_libs/lib/libmongoc2.dylib"));
        },
        .linux => {
            // Container specific configuration
            exe.root_module.addObjectFile(.{ .src_path = .{
                .owner = b,
                .sub_path = "/usr/lib/libmongoc-1.0.so.0",
            } });
            exe.root_module.addObjectFile(.{ .src_path = .{
                .owner = b,
                .sub_path = "/usr/lib/libbson-1.0.so.0",
            } });
        },
        else => @compileError("Unsupported platform"),
    }

    // const mongoc_translate = b.addSystemCommand(&.{
    //     "zig",
    //     "translate-c",
    //     "mongo_libs/include/mongoc-2.2.3/mongoc/mongoc.h",
    //     "-I",
    //     "mongo_libs/include/mongoc-2.2.3",
    //     "-I",
    //     "mongo_libs/include/bson-2.2.3",
    //     ">",
    //     "src/headers/mongoc.zig",
    // });
    // const bson_translate = b.addSystemCommand(&.{
    //     "zig",
    //     "translate-c",
    //     "mongo_libs/include/bson-2.2.3/bson/bson.h",
    //     "-I",
    //     "mongo_libs/include/mongoc-2.2.3",
    //     "-I",
    //     "mongo_libs/include/bson-2.2.3",
    //     ">",
    //     "src/headers/bson.zig",
    // });

    // b.getInstallStep().dependOn(&mongoc_translate.step);
    // b.getInstallStep().dependOn(&bson_translate.step);

    exe.root_module.addImport("mongoc", b.createModule(.{
        .root_source_file = b.path("src/headers/mongoc.zig"),
    }));
    exe.root_module.addImport("bson", b.createModule(.{
        .root_source_file = b.path("src/headers/bson.zig"),
    }));
}
