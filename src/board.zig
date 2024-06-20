const std = @import("std");

const engine = @import("engine.zig");
const board = @import("sudoku/board.zig");
const puzzle_gen = @import("sudoku/puzzle_gen.zig");
const solve = @import("sudoku/solve.zig");

pub const BoardResources = struct {
    mesh: engine.AssetId(engine.Mesh),

    base: engine.AssetId(engine.StandardMaterial),

    selected: [10]engine.AssetId(engine.StandardMaterial),
    unselected: [10]engine.AssetId(engine.StandardMaterial),

    pub fn fromWorld(world: *engine.World) !BoardResources {
        // get the assets from the world
        const images = world.resourcePtr(engine.Assets(engine.Image));
        const meshes = world.resourcePtr(engine.Assets(engine.Mesh));
        const materials = world.resourcePtr(engine.Assets(engine.StandardMaterial));

        var numbers: [9]engine.AssetId(engine.Image) = undefined;

        for (0..9) |i| {
            const path = try std.fmt.allocPrint(world.allocator, "assets/{}.qoi", .{i + 1});
            defer world.allocator.free(path);

            const image = try engine.Image.load_qoi(world.allocator, path);

            numbers[i] = try images.add(image);
        }

        // create the cube mesh for the numbers
        const mesh = try engine.Mesh.cube(world.allocator, 0.5, 0xffffffff);
        const mesh_handle = try meshes.add(mesh);

        const base_handle = try materials.add(
            engine.StandardMaterial{
                .color = engine.Color.rgb(0.4, 0.4, 0.4),
                .metallic = 0.91,
            },
        );

        var selected: [10]engine.AssetId(engine.StandardMaterial) = undefined;
        var unselected: [10]engine.AssetId(engine.StandardMaterial) = undefined;

        selected[0] = try materials.add(
            engine.StandardMaterial{
                .color = engine.Color.WHITE,
                .emissive = engine.Color.rgb(0.0, 1.0, 0.0),
                .emissive_strength = 1.0,
            },
        );

        unselected[0] = try materials.add(
            engine.StandardMaterial{
                .color = engine.Color.WHITE,
            },
        );

        for (1..10) |i| {
            // create the selected material
            const selected_handle = try materials.add(
                engine.StandardMaterial{
                    .color = engine.Color.WHITE,
                    .color_texture = numbers[i - 1],
                    .emissive = engine.Color.rgb(0.0, 1.0, 0.0),
                    .emissive_strength = 1.0,
                },
            );

            // create the unselected material
            const unselected_handle = try materials.add(
                engine.StandardMaterial{
                    .color = engine.Color.WHITE,
                    .color_texture = numbers[i - 1],
                },
            );

            selected[i] = selected_handle;
            unselected[i] = unselected_handle;
        }

        // return the resources
        return BoardResources{
            .mesh = mesh_handle,
            .base = base_handle,
            .selected = selected,
            .unselected = unselected,
        };
    }

    pub fn deinit(self: *BoardResources) void {
        self.mesh.deinit();

        for (self.selected) |material| {
            material.deinit();
        }

        for (self.unselected) |material| {
            material.deinit();
        }
    }
};

pub const Board = struct {
    selected: ?usize,

    numbers: std.ArrayList(engine.Entity),

    sudoku: board.DefaultBoard,

    pub fn deinit(self: *Board) void {
        self.sudoku.deinit();
        self.numbers.deinit();
    }
};

pub const SpawnBoard = struct {
    entity: engine.Entity,

    pub fn apply(self: *SpawnBoard, world: *engine.World) !void {
        const resources = try world.resourceOrInit(BoardResources);

        var numbers = std.ArrayList(engine.Entity).init(world.allocator);

        // var sudoku = try puzzle_gen.generate_puzzle(3, 3, 70, world.allocator);
        // errdefer sudoku.deinit();
        var sudoku: board.Board(3, 3, .MATRIX, .HEAP) = undefined;
        std.debug.print("beginning sudoku puzzle generation\n", .{});
        while (true) {
            std.debug.print("\tattempting to generate sudoku puzzle\n", .{});
            sudoku = puzzle_gen.generate_puzzle(3, 3, 20, world.allocator) catch continue;
            break;
        }
        errdefer sudoku.deinit();

        const size = engine.Vec3.init(
            @floatFromInt(sudoku.size - 1),
            @floatFromInt(sudoku.size - 1),
            0.0,
        ).add(0.2);

        const offset = size.div(-2.0);

        for (0..sudoku.size) |y| {
            for (0..sudoku.size) |x| {
                const cube = try world.spawn();

                const number = sudoku.get(.{ .i = x, .j = y });

                resources.mesh.increment();
                resources.unselected[number].increment();

                const position = engine.Vec3.init(
                    @as(f32, @floatFromInt(x)) + @as(f32, @floatFromInt(x / 3)) * 0.1,
                    @as(f32, @floatFromInt(y)) + @as(f32, @floatFromInt(y / 3)) * 0.1,
                    0.0,
                );

                try cube.addComponent(resources.mesh);
                try cube.addComponent(resources.unselected[number]);
                try cube.addComponent(engine.Transform{
                    .translation = position.add(offset),
                });
                try cube.addComponent(engine.GlobalTransform{});

                try numbers.append(cube.entity);

                try world.setParent(cube.entity, self.entity);
            }
        }

        resources.mesh.increment();
        resources.base.increment();

        const base = try world.spawn();
        try base.addComponent(resources.mesh);
        try base.addComponent(resources.base);
        try base.addComponent(engine.Transform{
            .scale = size.add(engine.Vec3.init(1.5, 1.5, 0.4)),
        });
        try base.addComponent(engine.GlobalTransform{});

        try world.setParent(base.entity, self.entity);

        const root = world.entity(self.entity);
        try root.addComponent(engine.Transform{});
        try root.addComponent(engine.GlobalTransform{});
        try root.addComponent(Board{
            .sudoku = sudoku,
            .selected = null,
            .numbers = numbers,
        });
    }
};

pub fn spawnBoard(commands: engine.Commands) !engine.Entity {
    const root = try commands.spawn();
    const entity = root.entity;

    try commands.append(SpawnBoard{
        .entity = entity,
    });

    return entity;
}

const MaterialQuery = engine.Query(struct {
    material: *engine.AssetId(engine.StandardMaterial),
});

fn updateBoardNumbers(
    board_: *const Board,
    resources: *BoardResources,
    materials: MaterialQuery,
) !void {
    for (board_.numbers.items, 0..) |entity, i| {
        const coord = .{
            .i = i % board_.sudoku.size,
            .j = i / board_.sudoku.size,
        };

        if (materials.fetch(entity)) |m| {
            const number = board_.sudoku.get(coord);

            m.material.decrement();
            m.material.* = resources.unselected[number];
            m.material.increment();
        }
    }
}

pub fn boardInputSystem(
    allocator: std.mem.Allocator,
    inputs: engine.EventReader(engine.Window.KeyInput),
    resources: *BoardResources,
    boards: engine.Query(struct {
        board: *Board,
    }),
    materials: MaterialQuery,
) !void {
    while (inputs.next()) |input| {
        if (!input.is_pressed) continue;
        const key = input.key orelse continue;

        var it = boards.iterator();
        while (it.next()) |q| {
            var selected = q.board.selected orelse 0;

            const size = q.board.sudoku.size * q.board.sudoku.size;

            switch (key) {
                .Right => {
                    const oldy = selected / q.board.sudoku.size;
                    selected += 1;
                    const newy = selected / q.board.sudoku.size;
                    if (oldy < newy) {
                        selected -= q.board.sudoku.size;
                    }
                    selected %= size;
                },
                .Left => {
                    const oldy = (selected + size) / q.board.sudoku.size;
                    selected += size - 1;
                    const newy = selected / q.board.sudoku.size;
                    if (oldy > newy) {
                        selected += q.board.sudoku.size;
                    }
                    selected %= size;
                },
                .Up => {
                    selected += q.board.sudoku.size;
                    selected %= size;
                },
                .Down => {
                    selected += size - q.board.sudoku.size;
                    selected %= size;
                },
                .P => {
                    _ = try solve.solve(.WFC, &q.board.sudoku, allocator);
                    try updateBoardNumbers(q.board, resources, materials);
                },
                .C => {
                    q.board.sudoku.clear();
                    try updateBoardNumbers(q.board, resources, materials);
                },
                .R => {
                    q.board.sudoku.deinit();

                    // var sudoku = try puzzle_gen.generate_puzzle(3, 3, 70, world.allocator);
                    // errdefer sudoku.deinit();

                    var sudoku: board.Board(3, 3, .MATRIX, .HEAP) = undefined;
                    std.debug.print("beginning sudoku puzzle generation\n", .{});
                    while (true) {
                        std.debug.print("\tattempting to generate sudoku puzzle\n", .{});
                        sudoku = puzzle_gen.generate_puzzle(3, 3, 20, allocator) catch continue;
                        break;
                    }
                    errdefer sudoku.deinit();

                    q.board.sudoku = sudoku;

                    try updateBoardNumbers(q.board, resources, materials);
                },
                .Num1, .Num2, .Num3, .Num4, .Num5, .Num6, .Num7, .Num8, .Num9 => {
                    const number = @intFromEnum(key) - @intFromEnum(engine.Window.Key.Num0);
                    const coord = .{
                        .i = selected % q.board.sudoku.size,
                        .j = selected / q.board.sudoku.size,
                    };

                    if (q.board.sudoku.is_safe_move(coord, @intCast(number))) {
                        q.board.sudoku.set(coord, @intCast(number));
                    }
                },
                else => {},
            }

            if (q.board.selected) |s| {
                const number = q.board.sudoku.get(.{
                    .i = s % q.board.sudoku.size,
                    .j = s / q.board.sudoku.size,
                });

                if (materials.fetch(q.board.numbers.items[s])) |m| {
                    m.material.decrement();
                    m.material.* = resources.unselected[number];
                    m.material.increment();
                }
            }

            const number = q.board.sudoku.get(.{
                .i = selected % q.board.sudoku.size,
                .j = selected / q.board.sudoku.size,
            });

            if (materials.fetch(q.board.numbers.items[selected])) |m| {
                m.material.decrement();
                m.material.* = resources.selected[number];
                m.material.increment();
            }

            q.board.selected = selected;
        }
    }
}
