//
// extra ImGui tools
//

DragFloat3 :: (label: string, data: *[3]float) -> bool #expand { return DragFloat3(temp_c_string(label), data); }
DragFloat4 :: (label: string, data: *[4]float) -> bool #expand { return DragFloat4(temp_c_string(label), data); }

InputText :: (
    label: string,
    str: *string,
    flags: ImGui.InputTextFlags = 0,
    cb: InputTextCallback = null,
    cb_userdata: *void = null
) -> bool {
    flags |= .CallbackResize;
    flags |= .CallbackEdit;

    ud := InputTextCallbackUserData.{
        str = str,
        chain_cb = cb,
        chain_cb_userdata = cb_userdata,
    };

    c_str: *u8 = talloc(str.count+1);
    memset(c_str, 0, str.count+1);
    memcpy(c_str, str.data, str.count);
    return ImGui.InputText(temp_c_string(label), c_str, cast(u64)(str.count+1), flags, input_text_cb, *ud);
}

PushGroup :: () #expand {
    ImGui.BeginGroup();
    `defer ImGui.EndGroup();
}

PushPopFont :: (font: *ImGui.ImFont, font_size_base_unscaled: float = 0 /* zero means keep the base */) #expand {
    ImGui.PushFont(font, font_size_base_unscaled);
    `defer ImGui.PopFont();
}

PushPopID :: (id_str: string) #expand {
    ImGui.PushID(id_str);
    `defer ImGui.PopID();
}

PushPopID :: (id_ptr: *void) #expand {
    ImGui.PushID(id_ptr);
    `defer ImGui.PopID();
}

PushPopStyleColor :: (idx: ImGui.Col, col: ImGui.ImVec4) #expand {
    ImGui.PushStyleColor(idx, col);
    `defer ImGui.PopStyleColor();
}

PushPopStyleVar :: (idx: ImGui.StyleVar, var: ImGui.ImVec2) #expand {
    ImGui.PushStyleVar(idx, var);
    `defer ImGui.PopStyleVar();
}

PushPopStyleVar :: (idx: ImGui.StyleVar, var: float) #expand {
    ImGui.PushStyleVar(idx, var);
    `defer ImGui.PopStyleVar();
}

PushPopIndent :: (indent: float) #expand {
    ImGui.Indent(indent);
    `defer ImGui.Unindent(indent);
}

BeginEndTooltip :: () #expand {
    ImGui.BeginTooltip();
    `defer ImGui.EndTooltip();
}

PushPopTextWrapPos :: (size: float) #expand {
    ImGui.PushTextWrapPos(size);
    `defer ImGui.PopTextWrapPos();
}

BeginEnd_return :: (name: string, open: *bool) #expand {
    `defer ImGui.End();
    if !ImGui.Begin(name, open)
        `return;
}

BeginEndMenu :: (name: string, code: Code) #expand {
    using ImGui;

    if BeginMenu(name) {
        defer EndMenu();
        #insert code;
    }
}


#scope_file

using ImGui :: #import "ImGui";
#import "Basic";

InputTextCallbackUserData :: struct {
    str: *string;
    chain_cb: ImGui.InputTextCallback;
    chain_cb_userdata: *void;
}

input_text_cb :: (data: *ImGui.InputTextCallbackData) -> s32 #c_call {
    push_context {
        using cb_userdata := cast(*InputTextCallbackUserData)data.UserData;

        if data.EventFlag == {
            case .CallbackResize;
                array_resize(cast(*[]u8)str, data.BufTextLen);
                c_str: *u8 = talloc(str.count+1);
                memset(c_str, 0, str.count+1);
                memcpy(c_str, str.data, str.count);
                data.Buf = c_str;
            case .CallbackEdit;
                reset_string(str);
                str.* = copy_string(to_string(data.Buf));
             case;
                print("Other callback %\n", data.EventFlag);
        }

        if chain_cb {
            data.UserData = chain_cb_userdata;
            return chain_cb(data);
        }
    }

    return 0;
}

reset_string :: (str: *string) {
    if str.count free(str.data);
    str.count = 0;
}
