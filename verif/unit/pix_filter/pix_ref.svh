// Independent integer reference for pix-spec 2.1 and 2.4.
function automatic int gray_ref(input logic [23:0] rgb);
    return (77*int'(rgb[23:16]) + 150*int'(rgb[15:8]) + 29*int'(rgb[7:0]) + 128)/256;
endfunction

function automatic int clamp_ref(input int v);
    return v < 0 ? 0 : (v > 255 ? 255 : v);
endfunction

function automatic logic [23:0] window_ref(input int op, input logic [215:0] win);
    int p[9];
    int y[9];
    int value;
    int gx;
    int gy;
    logic [23:0] result;
    for (int n=0; n<9; n++) y[n] = gray_ref(win[n*24 +: 24]);
    result = win[96 +: 24];
    if (op >= 1 && op <= 3) begin
        for (int c=0; c<3; c++) begin
            for (int n=0; n<9; n++) p[n] = int'(win[n*24+c*8 +: 8]);
            case (op)
                1: begin
                    value=4;
                    foreach (p[n]) value += p[n];
                    value /= 9;
                end
                2: value=(p[0]+2*p[1]+p[2]+2*p[3]+4*p[4]+2*p[5]+p[6]+2*p[7]+p[8]+8)/16;
                default: value=clamp_ref(5*p[4]-p[1]-p[3]-p[5]-p[7]);
            endcase
            result[c*8 +: 8] = 8'(value);
        end
    end else if (op >= 4 && op <= 6) begin
        case (op)
            4: begin
                gx = -y[0]+y[2]-2*y[3]+2*y[5]-y[6]+y[8];
                gy = -y[0]-2*y[1]-y[2]+y[6]+2*y[7]+y[8];
                value = clamp_ref((gx<0 ? -gx : gx) + (gy<0 ? -gy : gy));
            end
            5: begin
                value=255;
                foreach (y[n]) if (y[n]<value) value=y[n];
            end
            default: begin
                value=0;
                foreach (y[n]) if (y[n]>value) value=y[n];
            end
        endcase
        result = {8'(value),8'(value),8'(value)};
    end
    return result;
endfunction
