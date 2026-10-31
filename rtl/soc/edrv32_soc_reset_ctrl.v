// File: edrv32_soc_reset_ctrl.v
// Spec: sys-subsys-spec 2.10; edrv32-soc-spec 5.2 X8, 5.3.
// Description: Sequence power-on and sixteen-system-clock software resets.
//              Keep the memory fabric running during either software reset.
// Clock domain: clk_sys, clk_mem, clk_pix, clk_npu, cam0, cam1, eth_rx and eth_tx.
module edrv32_soc_reset_ctrl (
    // Clocks and external asynchronous reset.
    input wire clk_sys_i,
    input wire clk_mem_i,
    input wire clk_pix_i,
    input wire clk_npu_i,
    input wire clk_cam0_i,
    input wire clk_cam1_i,
    input wire clk_eth_rx_i,
    input wire clk_eth_tx_i,
    input wire rst_n_i,

    // Ready level and clk_sys software request pulses.
    input wire mem_ready_i,
    input wire soft_reset_media_i,
    input wire soft_reset_soc_i,

    // Resets synchronously released in their respective domains.
    output wire rst_sys_por_n_o,
    output wire rst_sys_n_o,
    output wire rst_mem_core_n_o,
    output wire rst_mem_n_o,
    output wire rst_pix_n_o,
    output wire rst_npu_n_o,
    output wire rst_cam0_n_o,
    output wire rst_cam1_n_o,
    output wire rst_eth_rx_n_o,
    output wire rst_eth_tx_n_o
);
    wire rst_mem_por_n_w;
    wire mem_ready_w;
    wire mem_released_w;
    wire rst_mem_copy_n_w;
    wire media_release_n_w;
    wire sys_release_n_w;
    wire soft_active_w;
    reg [4:0] soft_cnt_r;
    reg soft_soc_r;
    reg sys_release_r;

    // Always-on control logic cannot use a reset which it generates itself.
    edrv32_reset_sync u_sys_por (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_por_n_o)
    );
    edrv32_reset_sync u_mem_por (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_mem_por_n_w)
    );
    edrv32_cdc_sync_bit u_mem_ready (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_por_n_w),
        .bit_i(mem_ready_i),
        .bit_o(mem_ready_w)
    );
    edrv32_reset_sync u_mem_core (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_n_i && mem_ready_w),
        .rst_n_o(rst_mem_core_n_o)
    );

    // spec 2.10: the counter survives the resets requested by software.
    always @(posedge clk_sys_i or negedge rst_sys_por_n_o) begin
        if (!rst_sys_por_n_o) begin
            soft_cnt_r <= 5'd0;
            soft_soc_r <= 1'b0;
        end else if (soft_reset_soc_i || soft_reset_media_i) begin
            soft_cnt_r <= 5'd16;
            soft_soc_r <= soft_reset_soc_i;
        end else if (soft_active_w) begin
            soft_cnt_r <= soft_cnt_r - 1'b1;
            if (soft_cnt_r == 5'd1) begin
                soft_soc_r <= 1'b0;
            end
        end
    end
    assign soft_active_w = soft_cnt_r != 5'd0;
    assign media_release_n_w = rst_mem_core_n_o && !soft_active_w;

    edrv32_reset_sync u_mem (
        .clk_i(clk_mem_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_mem_n_o)
    );
    edrv32_reset_sync u_npu (
        .clk_i(clk_npu_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_npu_n_o)
    );
    edrv32_reset_sync u_pix (
        .clk_i(clk_pix_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_pix_n_o)
    );
    edrv32_reset_sync u_cam0 (
        .clk_i(clk_cam0_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_cam0_n_o)
    );
    edrv32_reset_sync u_cam1 (
        .clk_i(clk_cam1_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_cam1_n_o)
    );
    edrv32_reset_sync u_eth_rx (
        .clk_i(clk_eth_rx_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_eth_rx_n_o)
    );
    edrv32_reset_sync u_eth_tx (
        .clk_i(clk_eth_tx_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_eth_tx_n_o)
    );

    // spec 2.10 release order: all one-stage memory copies release first.
    edrv32_reset_copy u_mem_copy (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_o),
        .rst_n_o(rst_mem_copy_n_w)
    );
    edrv32_cdc_sync_bit u_mem_released (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_por_n_o && !soft_soc_r),
        .bit_i(rst_mem_copy_n_w),
        .bit_o(mem_released_w)
    );
    // A media-only reset must not revoke a previously released system reset.
    always @(posedge clk_sys_i or negedge rst_sys_por_n_o) begin
        if (!rst_sys_por_n_o) begin
            sys_release_r <= 1'b0;
        end else if (soft_reset_soc_i || soft_soc_r) begin
            sys_release_r <= 1'b0;
        end else if (mem_released_w) begin
            sys_release_r <= 1'b1;
        end
    end
    assign sys_release_n_w = rst_n_i && sys_release_r && !soft_soc_r;
    edrv32_reset_sync u_sys (
        .clk_i(clk_sys_i),
        .rst_n_i(sys_release_n_w),
        .rst_n_o(rst_sys_n_o)
    );
endmodule
