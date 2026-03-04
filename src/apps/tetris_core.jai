#import "Math";

TETRIS_BOARD_W : s32 : 10;
TETRIS_BOARD_H : s32 : 22;
TETRIS_VISIBLE_H : s32 : 20;
TETRIS_SPAWN_X : s32 : 4;
TETRIS_SPAWN_Y : s32 : 20;
TETRIS_SOFT_DROP_POINTS : s32 : 1;
TETRIS_HARD_DROP_POINTS : s32 : 2;

Tetris_Piece :: enum u8 {
    I;
    O;
    T;
    S;
    Z;
    J;
    L;
}

Tetris_Offset :: struct {
    x: s32;
    y: s32;
}

Tetris_Clear_Event :: struct {
    rows: [4] s32;
    count: s32;
}

Tetris_Game :: struct {
    board: [TETRIS_BOARD_H][TETRIS_BOARD_W] u8;

    rng_state: u64;
    bag: [7] Tetris_Piece;
    bag_count: s32;

    active_piece: Tetris_Piece;
    active_rot: s32;
    active_x: s32;
    active_y: s32;
    active_valid: bool;

    game_over: bool;
    paused: bool;

    score: s32;
    level: s32;
    total_lines: s32;

    gravity_accum: float;
    clear_event: Tetris_Clear_Event;
}

tetris_piece_blocks :: (piece: Tetris_Piece, rot: s32) -> [4] Tetris_Offset {
    r := rot & 3;
    if piece == .I {
        if r == 0 return PIECE_I_0;
        if r == 1 return PIECE_I_1;
        if r == 2 return PIECE_I_2;
        return PIECE_I_3;
    }
    if piece == .O {
        if r == 0 return PIECE_O_0;
        if r == 1 return PIECE_O_1;
        if r == 2 return PIECE_O_2;
        return PIECE_O_3;
    }
    if piece == .T {
        if r == 0 return PIECE_T_0;
        if r == 1 return PIECE_T_1;
        if r == 2 return PIECE_T_2;
        return PIECE_T_3;
    }
    if piece == .S {
        if r == 0 return PIECE_S_0;
        if r == 1 return PIECE_S_1;
        if r == 2 return PIECE_S_2;
        return PIECE_S_3;
    }
    if piece == .Z {
        if r == 0 return PIECE_Z_0;
        if r == 1 return PIECE_Z_1;
        if r == 2 return PIECE_Z_2;
        return PIECE_Z_3;
    }
    if piece == .J {
        if r == 0 return PIECE_J_0;
        if r == 1 return PIECE_J_1;
        if r == 2 return PIECE_J_2;
        return PIECE_J_3;
    }

    if r == 0 return PIECE_L_0;
    if r == 1 return PIECE_L_1;
    if r == 2 return PIECE_L_2;
    return PIECE_L_3;
}

tetris_rng_next :: (state: *u64) -> u32 {
    // xorshift64*
    x := state.*;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    state.* = x;
    result := x * 2685821657736338717;
    return cast(u32) (result >> 32);
}

tetris_shuffle_bag :: (game: *Tetris_Game) {
    game.bag[0] = .I;
    game.bag[1] = .O;
    game.bag[2] = .T;
    game.bag[3] = .S;
    game.bag[4] = .Z;
    game.bag[5] = .J;
    game.bag[6] = .L;

    i := game.bag.count - 1;
    while i > 0 {
        r := cast(s32) (tetris_rng_next(*game.rng_state) % cast(u32) (i + 1));
        tmp := game.bag[i];
        game.bag[i] = game.bag[r];
        game.bag[r] = tmp;
        i -= 1;
    }
    game.bag_count = cast(s32) game.bag.count;
}

tetris_pop_piece :: (game: *Tetris_Game) -> Tetris_Piece {
    if game.bag_count <= 0 tetris_shuffle_bag(game);
    game.bag_count -= 1;
    return game.bag[game.bag_count];
}

tetris_board_cell :: (game: *Tetris_Game, x: s32, y: s32) -> u8 {
    if x < 0 || x >= TETRIS_BOARD_W return 1;
    if y < 0 return 1;
    if y >= TETRIS_BOARD_H return 0;
    return game.board[y][x];
}

tetris_can_place :: (game: *Tetris_Game, piece: Tetris_Piece, rot: s32, px: s32, py: s32) -> bool {
    blocks := tetris_piece_blocks(piece, rot);
    for 0..3 {
        bx := px + blocks[it].x;
        by := py + blocks[it].y;
        if bx < 0 || bx >= TETRIS_BOARD_W return false;
        if by < 0 return false;
        if by >= TETRIS_BOARD_H continue;
        if game.board[by][bx] != 0 return false;
    }
    return true;
}

tetris_try_spawn :: (game: *Tetris_Game) -> bool {
    piece := tetris_pop_piece(game);
    rot: s32 = 0;
    x: s32 = TETRIS_SPAWN_X;
    y: s32 = TETRIS_SPAWN_Y;

    if !tetris_can_place(game, piece, rot, x, y) {
        game.game_over = true;
        game.active_valid = false;
        return false;
    }

    game.active_piece = piece;
    game.active_rot = rot;
    game.active_x = x;
    game.active_y = y;
    game.active_valid = true;
    return true;
}

tetris_init_game :: (using game: *Tetris_Game, seed: u64 = cast(u64) 0x5eed) {
    game.* = .{};
    rng_state = ifx seed != 0 then seed else cast(u64) 0x5eed;
    score = 0;
    level = 1;
    total_lines = 0;
    tetris_shuffle_bag(game);
    tetris_try_spawn(game);
}

tetris_restart :: (game: *Tetris_Game, seed: u64 = cast(u64) 0x5eed) {
    tetris_init_game(game, seed);
}

tetris_clear_lines :: (game: *Tetris_Game) -> s32 {
    game.clear_event = .{};

    lines: s32 = 0;
    y: s32 = 0;
    while y < TETRIS_BOARD_H {
        full := true;
        for x: 0..TETRIS_BOARD_W-1 {
            if game.board[y][x] == 0 {
                full = false;
                break;
            }
        }

        if full {
            if game.clear_event.count < 4 {
                game.clear_event.rows[game.clear_event.count] = y;
                game.clear_event.count += 1;
            }

            yy := y;
            while yy < TETRIS_BOARD_H - 1 {
                game.board[yy] = game.board[yy + 1];
                yy += 1;
            }
            for x: 0..TETRIS_BOARD_W-1 game.board[TETRIS_BOARD_H - 1][x] = 0;
            lines += 1;
            continue;
        }
        y += 1;
    }

    if lines > 0 {
        game.total_lines += lines;
        game.level = 1 + game.total_lines / 10;

        base := lines * 250;
        if lines == 1 base = 100;
        if lines == 2 base = 300;
        if lines == 3 base = 500;
        if lines == 4 base = 800;
        game.score += base * game.level;
    }

    return lines;
}

tetris_lock_piece :: (game: *Tetris_Game) {
    if !game.active_valid return;

    blocks := tetris_piece_blocks(game.active_piece, game.active_rot);
    piece_id := cast(u8) game.active_piece + 1;
    for 0..3 {
        bx := game.active_x + blocks[it].x;
        by := game.active_y + blocks[it].y;
        if by >= 0 && by < TETRIS_BOARD_H && bx >= 0 && bx < TETRIS_BOARD_W {
            game.board[by][bx] = piece_id;
        }
    }

    tetris_clear_lines(game);
    tetris_try_spawn(game);
}

tetris_try_move :: (game: *Tetris_Game, dx: s32, dy: s32) -> bool {
    if !game.active_valid || game.game_over || game.paused return false;
    nx := game.active_x + dx;
    ny := game.active_y + dy;
    if !tetris_can_place(game, game.active_piece, game.active_rot, nx, ny) return false;
    game.active_x = nx;
    game.active_y = ny;
    return true;
}

tetris_try_rotate :: (game: *Tetris_Game, dir: s32) -> bool {
    if !game.active_valid || game.game_over || game.paused return false;

    new_rot := (game.active_rot + dir) & 3;
    kicks := Tetris_Offset.[
        .{0, 0},
        .{1, 0},
        .{-1, 0},
        .{2, 0},
        .{-2, 0},
        .{0, 1},
        .{0, -1},
    ];

    for kicks {
        nx := game.active_x + it.x;
        ny := game.active_y + it.y;
        if tetris_can_place(game, game.active_piece, new_rot, nx, ny) {
            game.active_x = nx;
            game.active_y = ny;
            game.active_rot = new_rot;
            return true;
        }
    }

    return false;
}

tetris_soft_drop :: (game: *Tetris_Game) -> bool {
    if tetris_try_move(game, 0, -1) {
        game.score += TETRIS_SOFT_DROP_POINTS;
        return true;
    }
    tetris_lock_piece(game);
    return false;
}

tetris_hard_drop :: (game: *Tetris_Game) -> s32 {
    if !game.active_valid || game.game_over || game.paused return 0;

    dist: s32 = 0;
    while tetris_try_move(game, 0, -1) dist += 1;
    game.score += dist * TETRIS_HARD_DROP_POINTS;
    tetris_lock_piece(game);
    return dist;
}

tetris_gravity_cps :: (level: s32) -> float {
    // Simple linearized gravity curve with a cap.
    cps := 1.0 + cast(float) (level - 1) * 0.22;
    if cps > 18.0 cps = 18.0;
    return cps;
}

tetris_tick :: (game: *Tetris_Game, dt: float) {
    if game.game_over || game.paused || !game.active_valid return;

    game.gravity_accum += dt * tetris_gravity_cps(game.level);
    steps := cast(s32) floor(game.gravity_accum);
    if steps <= 0 return;
    game.gravity_accum -= cast(float) steps;

    for 0..steps-1 {
        if !tetris_try_move(game, 0, -1) {
            tetris_lock_piece(game);
            break;
        }
    }
}

tetris_toggle_pause :: (game: *Tetris_Game) {
    if game.game_over return;
    game.paused = !game.paused;
}

tetris_active_cells :: (game: *Tetris_Game, out_cells: *[4] Tetris_Offset) -> s32 {
    if !game.active_valid return 0;
    blocks := tetris_piece_blocks(game.active_piece, game.active_rot);
    for 0..3 {
        out_cells.*[it] = .{
            x = game.active_x + blocks[it].x,
            y = game.active_y + blocks[it].y,
        };
    }
    return 4;
}

tetris_ghost_y :: (game: *Tetris_Game) -> s32 {
    if !game.active_valid return 0;
    y := game.active_y;
    while tetris_can_place(game, game.active_piece, game.active_rot, game.active_x, y - 1) y -= 1;
    return y;
}

#scope_file

PIECE_I_0 : [4] Tetris_Offset = .[.{-1, 0}, .{0, 0}, .{1, 0}, .{2, 0}];
PIECE_I_1 : [4] Tetris_Offset = .[.{1, -1}, .{1, 0}, .{1, 1}, .{1, 2}];
PIECE_I_2 : [4] Tetris_Offset = .[.{-1, 1}, .{0, 1}, .{1, 1}, .{2, 1}];
PIECE_I_3 : [4] Tetris_Offset = .[.{0, -1}, .{0, 0}, .{0, 1}, .{0, 2}];

PIECE_O_0 : [4] Tetris_Offset = .[.{0, 0}, .{1, 0}, .{0, 1}, .{1, 1}];
PIECE_O_1 : [4] Tetris_Offset = .[.{0, 0}, .{1, 0}, .{0, 1}, .{1, 1}];
PIECE_O_2 : [4] Tetris_Offset = .[.{0, 0}, .{1, 0}, .{0, 1}, .{1, 1}];
PIECE_O_3 : [4] Tetris_Offset = .[.{0, 0}, .{1, 0}, .{0, 1}, .{1, 1}];

PIECE_T_0 : [4] Tetris_Offset = .[.{-1, 0}, .{0, 0}, .{1, 0}, .{0, 1}];
PIECE_T_1 : [4] Tetris_Offset = .[.{0, -1}, .{0, 0}, .{0, 1}, .{1, 0}];
PIECE_T_2 : [4] Tetris_Offset = .[.{-1, 0}, .{0, 0}, .{1, 0}, .{0, -1}];
PIECE_T_3 : [4] Tetris_Offset = .[.{0, -1}, .{0, 0}, .{0, 1}, .{-1, 0}];

PIECE_S_0 : [4] Tetris_Offset = .[.{-1, 0}, .{0, 0}, .{0, 1}, .{1, 1}];
PIECE_S_1 : [4] Tetris_Offset = .[.{0, -1}, .{0, 0}, .{1, 0}, .{1, 1}];
PIECE_S_2 : [4] Tetris_Offset = .[.{-1, -1}, .{0, -1}, .{0, 0}, .{1, 0}];
PIECE_S_3 : [4] Tetris_Offset = .[.{-1, -1}, .{-1, 0}, .{0, 0}, .{0, 1}];

PIECE_Z_0 : [4] Tetris_Offset = .[.{-1, 1}, .{0, 1}, .{0, 0}, .{1, 0}];
PIECE_Z_1 : [4] Tetris_Offset = .[.{1, -1}, .{1, 0}, .{0, 0}, .{0, 1}];
PIECE_Z_2 : [4] Tetris_Offset = .[.{-1, 0}, .{0, 0}, .{0, -1}, .{1, -1}];
PIECE_Z_3 : [4] Tetris_Offset = .[.{0, -1}, .{0, 0}, .{-1, 0}, .{-1, 1}];

PIECE_J_0 : [4] Tetris_Offset = .[.{-1, 0}, .{0, 0}, .{1, 0}, .{-1, 1}];
PIECE_J_1 : [4] Tetris_Offset = .[.{0, -1}, .{0, 0}, .{0, 1}, .{1, 1}];
PIECE_J_2 : [4] Tetris_Offset = .[.{-1, 0}, .{0, 0}, .{1, 0}, .{1, -1}];
PIECE_J_3 : [4] Tetris_Offset = .[.{0, -1}, .{0, 0}, .{0, 1}, .{-1, -1}];

PIECE_L_0 : [4] Tetris_Offset = .[.{-1, 0}, .{0, 0}, .{1, 0}, .{1, 1}];
PIECE_L_1 : [4] Tetris_Offset = .[.{0, -1}, .{0, 0}, .{0, 1}, .{1, -1}];
PIECE_L_2 : [4] Tetris_Offset = .[.{-1, 0}, .{0, 0}, .{1, 0}, .{-1, -1}];
PIECE_L_3 : [4] Tetris_Offset = .[.{0, -1}, .{0, 0}, .{0, 1}, .{-1, 1}];
