Token :: struct {
    kind: enum { STRING_PIECE; EXPR; };
    s: string;
}

is_ident_start :: (c: u8) -> bool {
    return (c >= #char "a" && c <= #char "z") || (c >= #char "A" && c <= #char "Z") || c == #char "_";
}

is_ident_continue :: (c: u8) -> bool {
    return is_ident_start(c) || (c >= #char "0" && c <= #char "9");
}

lex_template :: (input: string) -> [] Token {
    tokens: [..] Token;

    i: s64 = 0;
    segment_start: s64 = 0;

    while i < input.count {
        c := input[i];
        if c != #char "{" || i + 1 >= input.count || input[i + 1] != #char "{" {
            i += 1;
            continue;
        }

        // Flush preceding literal text.
        if i > segment_start {
            array_add(*tokens, .{
                kind = .STRING_PIECE,
                s = String.slice(input, segment_start, i - segment_start),
            });
        }

        j := i + 2;
        found_close := false;
        while j + 1 < input.count {
            if input[j] == #char "}" && input[j + 1] == #char "}" {
                found_close = true;
                break;
            }
            j += 1;
        }
        assert(found_close, "Unmatched '{{' in template string.");

        expr_raw := String.slice(input, i + 2, j - (i + 2));
        expr := String.trim(expr_raw);
        array_add(*tokens, .{ .EXPR, expr });

        i = j + 2;
        segment_start = i;
    }

    if segment_start < input.count {
        array_add(*tokens, .{ .STRING_PIECE, String.slice(input, segment_start, input.count - segment_start) });
    }

    return tokens;
}

main :: () {
    input := "simple: {{foo}} - complex: {{foo + bar}} blah";
    tokens := lex_template(input);

    expected := Token.[
        .{.STRING_PIECE, "simple: "},
        .{.EXPR,         "foo"},
        .{.STRING_PIECE, " - complex: "},
        .{.EXPR,         "foo + bar"},
        .{.STRING_PIECE, " blah"},
    ];

    assert(tokens.count == expected.count, "Expected % tokens, got %", expected.count, tokens.count);

    for expected {
        got := tokens[it_index];
        assert(got.kind == it.kind, "Token % kind mismatch: got %, expected %", it_index, got.kind, it.kind);
        assert(got.s == it.s,       "Token % text mismatch: got '%', expected '%'", it_index, got.s, it.s);
    }

    for tokens {
        log("[%] {kind=.%, s=\"%\"}", it_index, it.kind, it.s);
    }
}

#scope_file
#import "Basic";
String :: #import "String";
