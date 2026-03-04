#import "Basic";
#load "tetris_core.jai";

assert_true :: (ok: bool, message: string) {
    if ok return;
    log_error("tetris_core_tests failed: %", message);
    exit(1);
}

test_spawn_and_drop :: () {
    game: Tetris_Game;
    tetris_init_game(*game, 12345);
    assert_true(game.active_valid, "expected active piece after init");
    before_score := game.score;
    dist := tetris_hard_drop(*game);
    assert_true(dist > 0, "hard drop should move piece");
    assert_true(game.score > before_score, "hard drop should award score");
    occupied: s32 = 0;
    for y: 0..TETRIS_BOARD_H-1 {
        for x: 0..TETRIS_BOARD_W-1 {
            if game.board[y][x] != 0 occupied += 1;
        }
    }
    assert_true(occupied >= 4, "board should contain locked blocks after hard drop");
}

test_line_clear :: () {
    game: Tetris_Game;
    tetris_init_game(*game, 1);
    for y: 0..TETRIS_BOARD_H-1 {
        for x: 0..TETRIS_BOARD_W-1 game.board[y][x] = 0;
    }

    for x: 0..TETRIS_BOARD_W-1 game.board[0][x] = 1;
    game.board[0][4] = 0;

    game.active_piece = .I;
    game.active_rot = 1;
    game.active_x = 3;
    game.active_y = 0;
    game.active_valid = true;
    game.game_over = false;
    game.paused = false;

    _ = tetris_hard_drop(*game);

    assert_true(game.total_lines >= 1, "expected at least one cleared line");
    assert_true(game.score >= 100, "line clear should score");
}

test_bag_contains_all_pieces :: () {
    game: Tetris_Game;
    tetris_init_game(*game, 987654321);

    seen: [7] bool;
    for 0..6 {
        p := tetris_pop_piece(*game);
        seen[cast(s32) p] = true;
    }
    for 0..6 {
        assert_true(seen[it], tprint("bag missing piece index %", it));
    }
}

test_rotation_near_wall :: () {
    game: Tetris_Game;
    tetris_init_game(*game, 777);
    for y: 0..TETRIS_BOARD_H-1 {
        for x: 0..TETRIS_BOARD_W-1 game.board[y][x] = 0;
    }
    game.active_piece = .L;
    game.active_rot = 0;
    game.active_x = 0;
    game.active_y = 10;
    game.active_valid = true;
    rotated := tetris_try_rotate(*game, 1);
    assert_true(rotated, "rotation near wall should be kicked");
    cells: [4] Tetris_Offset;
    _ = tetris_active_cells(*game, *cells);
    for cells {
        assert_true(it.x >= 0 && it.x < TETRIS_BOARD_W, "kicked piece must stay in board bounds");
    }
}

main :: () {
    test_spawn_and_drop();
    test_line_clear();
    test_bag_contains_all_pieces();
    test_rotation_near_wall();
    log("tetris_core_tests: all tests passed");
}
