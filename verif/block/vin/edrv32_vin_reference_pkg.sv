// File: edrv32_vin_reference_pkg.sv
// Spec: vin 2.2, 2.6; vin-testplan 4.
// Description: Source-only frame shaping, frame numbering and software ring selection.
// Clock domain: none; called by stimulus, never observes VIN implementation state.
`timescale 1ns/1ps
package edrv32_vin_reference_pkg;
    class vin_frame;
        int width;
        int height;
        int source;
        int slot;
        int stride;
        bit [31:0] base;
        bit [31:0] frame_id;
        bit incomplete;
        bit bus_error;
        logic [15:0] pixels[];

        function bit [31:0] done_info();
            return 32'(slot) | (32'(source)<<2) | (32'(incomplete)<<4)
                | (32'(bus_error)<<5);
        endfunction
    endclass

    class vin_reference;
        int discard[2];
        bit [31:0] frame_id[3];
        int last_slot[2];

        function new();
            reset();
        endfunction

        function void reset();
            foreach (discard[i]) discard[i] = 2;
            foreach (frame_id[i]) frame_id[i] = 0;
            foreach (last_slot[i]) last_slot[i] = -1;
        endfunction

        function void enable();
            foreach (discard[i]) discard[i] = 2;
        endfunction

        function bit output_frame(input int source_i);
            if (source_i < 2 && discard[source_i] != 0) begin
                discard[source_i]--;
                return 0;
            end
            return 1;
        endfunction

        function int allocate(input int channel_i,
            input int ring_i,
            input bit [3:0] busy_i);
            int slot;
            int first_slot;
            // spec vin 2.6: wrap an old allocation outside the new ring to slot zero.
            first_slot = last_slot[channel_i]+1;
            if (first_slot >= ring_i) first_slot = 0;
            for (int step = 0; step < ring_i; step++) begin
                slot = (first_slot+step) % ring_i;
                if (!busy_i[slot]) begin
                    last_slot[channel_i] = slot;
                    return slot;
                end
            end
            return -1;
        endfunction

        function vin_frame shape(input int source_i,
            input int width_i,
            input int height_i,
            input int raw_width_i,
            input int raw_height_i,
            input logic [15:0] image_i[]);
            vin_frame frame;
            frame = new;
            frame.width = width_i;
            frame.height = height_i;
            frame.source = source_i;
            frame.frame_id = frame_id[source_i]++;
            frame.incomplete = raw_width_i != width_i || raw_height_i != height_i;
            frame.pixels = new[width_i*height_i];
            for (int y = 0; y < height_i; y++) begin
                for (int x = 0; x < width_i; x++) begin
                    frame.pixels[y*width_i+x] = (y < raw_height_i && x < raw_width_i)
                        ? image_i[y*raw_width_i+x] : 16'b0;
                end
            end
            return frame;
        endfunction
    endclass

    task automatic reference_selftest();
        vin_reference model;
        vin_frame frame;
        logic [15:0] raw[];
        int actual;
        model = new;
        raw = new[6];
        raw[0] = 16'h1234;
        raw[1] = 16'h5678;
        raw[2] = 16'h9abc;
        raw[3] = 16'hdef0;
        raw[4] = 16'h2468;
        raw[5] = 16'h1357;
        repeat (2) begin
            actual = int'(model.output_frame(0));
            if (actual != 0)
                $fatal(1, "FAIL discard expected=0 actual=%0d time=%0t", actual, $time);
        end
        if (!model.output_frame(0))
            $fatal(1, "FAIL third frame expected=1 actual=0 time=%0t", $time);
        frame = model.shape(0, 4, 3, 2, 3, raw);
        if (frame.pixels.size() != 12 || frame.pixels[0] != 16'h1234
            || frame.pixels[1] != 16'h5678 || frame.pixels[2] != 0
            || frame.pixels[4] != 16'h9abc || frame.pixels[11] != 0
            || !frame.incomplete || frame.frame_id != 0)
            $fatal(1, "FAIL shape padding expected=1234,5678,0;id0 actual=%p time=%0t",
                frame.pixels, $time);
        frame = model.shape(0, 2, 2, 3, 2, raw);
        if (frame.pixels[2] != 16'hdef0 || frame.pixels[3] != 16'h2468
            || frame.frame_id != 1 || !frame.incomplete)
            $fatal(1, "FAIL shape crop expected=def0,2468;id1 actual=%p time=%0t",
                frame.pixels, $time);
        frame = model.shape(1, 2, 4, 2, 3, raw);
        if (frame.pixels[6] != 0 || frame.frame_id != 0)
            $fatal(1, "FAIL missing row expected=0,id0 actual=%h,%h time=%0t",
                frame.pixels[6], frame.frame_id, $time);
        frame = model.shape(2, 2, 3, 2, 3, raw);
        if (frame.incomplete || frame.frame_id != 0 || frame.pixels[5] != 16'h1357)
            $fatal(1, "FAIL memory shape expected=complete,id0,1357 actual=%b,%h,%h time=%0t",
                frame.incomplete, frame.frame_id, frame.pixels[5], $time);
        model.enable();
        actual = int'(model.output_frame(0));
        if (actual != 0 || model.frame_id[0] != 2)
            $fatal(1, "FAIL re-enable expected=discard,id2 actual=%0d,%h time=%0t",
                actual, model.frame_id[0], $time);
        model.frame_id[2] = 'hffffffff;
        frame = model.shape(2, 2, 3, 2, 3, raw);
        if (frame.frame_id != 'hffffffff || model.frame_id[2] != 0)
            $fatal(1, "FAIL ID wrap expected=ffffffff,0 actual=%h,%h time=%0t",
                frame.frame_id, model.frame_id[2], $time);
        for (int ring = 2; ring <= 4; ring++) begin
            model.last_slot[0] = -1;
            for (int i = 0; i < ring*2; i++) begin
                actual = model.allocate(0, ring, 0);
                if (actual != i%ring)
                    $fatal(1, "FAIL ring expected=%0d actual=%0d time=%0t",
                        i%ring, actual, $time);
            end
            actual = model.allocate(0, ring, 4'hf);
            if (actual != -1)
                $fatal(1, "FAIL full ring expected=-1 actual=%0d time=%0t", actual, $time);
            actual = model.allocate(0, ring, 4'he);
            if (actual != 0)
                $fatal(1, "FAIL busy skip expected=0 actual=%0d time=%0t", actual, $time);
        end
        for (int ring = 2; ring <= 3; ring++) begin
            model.last_slot[0] = ring;
            actual = model.allocate(0, ring, 0);
            if (actual != 0)
                $fatal(1, "FAIL ring shrink ring=%0d previous=%0d expected=0 actual=%0d time=%0t",
                    ring, ring, actual, $time);
        end
        $display("PASS VIN reference selftest: shaping, discard, source IDs, ring 2/3/4");
    endtask
endpackage
